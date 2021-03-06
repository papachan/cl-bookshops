(defpackage bookshops-web
  (:use :cl
        :bookshops.models
        :hunchentoot
        :log4cl)
  (:import-from :easy-routes
                :routes-acceptor
                :defroute)
  (:import-from :bookshops.datasources.dilicom
                :search-books)
  (:local-nicknames (#:dilicom #:bookshops.datasources.dilicom)
                    (#:fr #:bookshops.datasources.scraper-fr)))

(in-package :bookshops-web)

#|
Show the stock on a web page.
(in construction)

(connect)
then
(start-app)

and go to localhost:4242/stock/

In this file:
- custom Djula filters
- templates loading
- routes
- server start/stop

Dev helpers:
- adding ?raw=t on a URL (on a card page)
|#

(defvar *server* nil
  "Current instance of easy-acceptor.")

;;; Djula filters.
(djula:def-filter :price (val)
  (format nil "~,2F" val))

(djula:def-filter :url (card)
  "Create a full URL to uniquely identify this card."
  (format nil "/~a/~a-~a"
          "card"                       ; this can be translated
          (mito:object-id card)
          ;; the slug won't actually be read back, only the id.
          (slug:slugify (title card))))

(djula:def-filter :quantity (card)
  (format nil "~a" (quantity card)))

(djula:def-filter :name (obj)
  (format nil "~a" (name obj)))

(djula:def-filter :describe (card)
  (with-output-to-string (s)
    (describe card s)))


;;; Load templates.
(djula:add-template-directory
 (asdf:system-relative-pathname "bookshops" "src/web/templates/"))
(defparameter +base.html+ (djula:compile-template* "base.html"))
(defparameter +dashboard.html+ (djula:compile-template* "dashboard.html"))
(defparameter +search.html+ (djula:compile-template* "search.html"))
(defparameter +stock.html+ (djula:compile-template* "stock.html"))
(defparameter +card-page.html+ (djula:compile-template* "card-page.html"))

(defparameter +404.html+ (djula:compile-template* "404.html"))

;;; Routes.
(defroute home-route ("/") ()
  (djula:render-template* +dashboard.html+ nil
                          :route "/"
                          :data (list :nb-titles (bookshops.models:count-book)
                                      :nb-books (bookshops.models::total-quantities)
                                      :nb-titles-negative (length
                                                           (bookshops.models::negative-quantities)))))

(defroute stock-route ("/stock") (&get q)
  (let ((cards (cond
                 ((bookshops.models::isbn-p q)
                  (list (find-by :isbn q)))
                 (q
                  (find-book :query (bookshops.utils::asciify q)))
                 (t
                  ;: XXX: pagination
                  (subseq (find-book)
                          0
                          (min 50 (bookshops.models::count-book)))))))
    (djula:render-template* +stock.html+ nil
                            :route "/stock"
                            :cards cards
                            :data (list :nb-titles (bookshops.models:count-book)
                                        :nb-books (bookshops.models::total-quantities)
                                        :nb-titles-negative (length
                                                             (bookshops.models::negative-quantities))))))

(defroute search-route ("/search") (&get q)
  (cond
    ;; ISBN? Dilicom search.
    ((bookshops.utils::isbn-p q)
     (let* ((res (dilicom:search-books (list q)))
            ;; The template accepts non-book objects,
            ;; it is not necessary to transform the data.
            ;; (cards (bookshops.models::data2books res))
            (cards (bookshops.models::check-in-stock res)))
       (djula:render-template* +search.html+ nil
                               :route "/search"
                               :q q
                               :cards cards
                               :nb-results (length cards)
                               :title (format nil "OpenBookstore - search: ~a" q))))

    ;; Free search? Other datasources.
    ((not (str:blank? q))
     (let* ((res (fr:books q))
            (cards (bookshops.models::check-in-stock res)))
       (djula:render-template* +search.html+ nil
                               :route "/search"
                               :q q
                               :cards cards
                               :nb-results (length cards)
                               :title (format nil "OpenBookstore - search: ~a" q))))

    ;;
    (t
     (djula:render-template* +search.html+ nil
                             :route "/search"
                             :q q
                             :messages (list "Please enter an ISBN or some keywords.")))))


(defroute card-page ("/card/:slug") (&get raw)
  "Show a card.

  If the URL parameter RAW is \"t\" (the string), then display the card object literally (with describe)."
  (let* ((card-id (ignore-errors
                    (parse-integer (first (str:split "-" slug)))))
         (card (when card-id
                 (mito:find-dao 'book :id card-id))))
    (cond
      ((null card-id)
       (djula:render-template* +404.html+ nil))
      (card
       (djula:render-template* +card-page.html+ nil
                               :card card
                               :places-copies (bookshops.models::book-places-quantities card)
                               :raw raw))
      (t
       (djula:render-template* +404.html+ nil)))))


(defun start-app (&key (port 4242))
  (bookshops.models:connect)
  (setf *server* (make-instance 'routes-acceptor :port port))
  (start *server*))

(defun stop-app ()
  ;; disconnect db ?
  (stop *server*))
