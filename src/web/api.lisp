(in-package :bookshops-web)

#+nil
(log:config :debug)

(defroute api-card-add-one ("/api/card/add" :method :post)
    (&post (id :parameter-type 'integer))
  (log:debug "Requested id: ~a.~&" id)
  (let ((card (mito:find-dao 'book :id id)))
    (when card
      (bookshops.models:add-to (bookshops.models:default-place) card))))

(defroute api-card-remove-one ("/api/card/remove" :method :post)
    (&post (id :parameter-type 'integer))
  (let ((card (mito:find-dao 'book :id id)))
    (when card
      (bookshops.models:add-to (bookshops.models:default-place)
                               card
                               :quantity -1))))
