(in-package :roguishly)
 
(print 'hi)

(defmacro pick (seq)
  `(elt ,seq (random ,(length seq))))

;; (defmacro ~zone~ ()
;;   '(zonemap (car *zones-above*)))




(defvar *level*)

(defun nop ())

(defclass cell ()
  ((x :accessor x
      :initarg :x
      :initform 0)
   (y :accessor y
      :initarg :y
      :initform 0)
   (tile :accessor tile
         :initarg :tile
         :initform #\#)
   (color :accessor color
          :initarg :color
          :initform :CGRAY)
   (items :accessor item
          :initarg :item
          :initform nil)
   (event :accessor event
          :initarg :event
          :initform #'nop)
   (vis :accessor vis
        :initarg :vis
        :initform nil)
   (pass :accessor pass
         :initarg :pass
         :initform nil)
   (you :accessor you
        :initform nil)
   (mob :accessor mob
        :initarg :mob
        :initform nil)))

(defclass floortile (cell)
  ((tile :accessor tile
         :initform #\.
         :initarg :tile)
   (vis :initform nil)
   (color :initform :CBLACK)
   (pass :accessor pass
         :initarg :pass
         :initform T)))

(defclass rock-cell (cell)
  ((pass :initform nil)
   (color :initform :CGRAY)
   (tile :initform (pick '(#\O #\o)))))

(defclass water-cell (cell)
  ((pass :initform T)
   (color :initform :CLBLUE)
   (tile :initform #\~)))


         

(defclass zone ()
  ((you :accessor you)
   (roomlist :accessor roomlist
             :initform '()
             :initarg roomlist)
   (zonemap :accessor zonemap
            :initform (init-zonemap)
            :initarg zonemap)))

(defun init-zonemap ()
  (let ((zm (make-array (list *height* *width*)
                        :element-type 'cell)))
    (loop for y below *height* do
         (loop for x below *width* do
              (setf (aref zm y x)
                    (make-instance 'cell
                                   :x x
                                   :y y
                                   :tile #\#
                                   :vis nil
                                   :pass nil))))
    zm))



;; zone map is hash of coords -> cells

(defclass thing ()
  ((x :accessor x)
   (y :accessor y)
   (color :accessor color
          :initform :CGRAY
          :initarg :color)          
   (icon :accessor icon
         :initform #\SPACE)))

(defclass mob (thing)
  ((x :accessor x
      :initform 0)
   (y :accessor y
      :initform 0)
   (icon :accessor icon)
   (inventory :accessor inventory
              :initform '())
   ($$$ :accessor $$$
        :initform 0)
   (action :accessor action
           :initform () ;; action is a symbolic expression that will be evalled.
           )))          ;; whenever the mob has a turn. it can be quite complex
                        ;; and incorporate timing, decision making, etc. 
;; this could be used as configurable idle or auto setting
;; when implemented in *you*

(defclass you (mob)
  ((icon :accessor icon
         :initform #\@)
   (color :accessor color
          :initform :CROSE
          :initarg :color)
   (glow :accessor glow
         :initarg :glow
         :initform 6)))


(defmethod pick-a-room ((zone zone))
  (elt (roomlist zone)
       (random (length (roomlist zone)))))

(defvar *you* (make-instance 'you))
(defvar *zones-above* '())
(defvar *zones-below* '())

;; =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
;; Movement of You
;; =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

(defun passable-p (y x)
  (and (>= x 0)
       (>= y 0)
       (< x *width*)
       (< y *height*)
       (not (block-p (aref (zonemap (car *zones-above*)) y x)))))

(defgeneric try-move (moveable y x))
(defgeneric left (mob))
(defgeneric right (mob))
(defgeneric up (mob))
(defgeneric down (mob))


(defun vacate (y x)
  (setf (you (aref (zonemap (car *zones-above*)) y x)) nil))
(defun occupy (y x you)
  (setf (you (aref (zonemap (car *zones-above*)) y x)) you))

(defmethod try-move ((you you) y x)
  ;; nb: fails silently if obstacle is hit
  (cond ((passable-p y x)
         (vacate (y you) (x you))
         (setf (x you) x
               (y you) y)
         (occupy y x you)
         (funcall (event (aref (zonemap (car *zones-above*)) y x))))
        (:OTHERWISE (format t "PATH OBSTRUCTED AT Y: ~D, X: ~D~%" y x))))

;; refactor as macros?

(defmethod left ((you you))
  (let ((x (1- (x you)))
        (y (y you)))
    (try-move you y x)))

(defmethod right ((you you))
  (let ((x (1+ (x you)))
        (y (y you)))
    (try-move you y x)))

(defmethod up ((you you))
  (let ((x (x you))
        (y (1- (y you))))
    (try-move you y x)))

(defmethod down ((you you))
  (let ((x (x you))
        (y (1+ (y you))))
    (try-move you y x)))
  
;; =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

(defun clear-map ()
  (setf (zonemap (car *zones-above*)) (make-array (list *height* *width*)
                           :element-type 'cell))
  (loop for i below (* *height* *width*) do
       (setf (row-major-aref (zonemap (car *zones-above*)) i)
             (make-instance 'cell))))



(defun read-zonemap (filename)
  ;; note that curses usually passes coords as y,x, not x,y
  ;; i.e. row, column
  (let ((x 0)
        (y 0)
        (zone (make-instance 'zone)))

    (with-open-file (stream filename :direction :input)
      (loop for byte = (read-char stream nil nil)
         while byte do
           (format t "~c" byte)
           (setf (tile (aref (zonemap zone) y x)) byte)
           (if (char= byte #\NEWLINE)
               (progn
                 (setf x 0)
                 (incf y))
               (incf x))))
    zone))

(defparameter blocking-tiles
  '(#\| #\- #\# #\= #\+ #\\ #\/
    #\o #\O #\SPACE))

(defun block-p (cell)
  (or (not (pass cell))
      (member (tile cell) blocking-tiles)))


;; (defun you-are-here (y x)
;;   (and (= (x *you*) x)
;;        (= (y *you*) y)))

(defmethod draw-tile ((cell cell) y x)
  (let* (;;(cell (aref zm y x))
         (tile (cond ((item cell) (icon (item cell)))
                     ((mob cell) (icon (mob cell)))
                     ((you cell) (icon (you cell)))
                     ((vis cell) (tile cell))
                     (:OTHERWISE #\SPACE)))
         (color (cond ((item cell) (color (item cell)))
                      ((mob cell) (color (mob cell)))
                      ((you cell) (color (you cell)))
                      ((can-see *you* (y cell) (x cell)) :CWHITE)
                      (:OTHERWISE (color cell)))))
    (attrset color)
    (mvaddch y x tile)))
          

(defvar *window-width* 50)
(defvar *window-height* 30)
(defun slide (y x &key (focus *you*))
  (let* ((mid-y (round (/ *window-height* 2)))
         (mid-x (round (/ *window-width* 2)))
         (dy (- mid-y (y focus)))
         (dx (- mid-x (x focus)))
         (slid-y (+ y dy))
         (slid-x (+ x dx)))
    (values
     (if (< 0 slid-y *window-height*) slid-y -1)
     (if (< 0 slid-x *window-width*) slid-x -1))))

(defun display-map (&optional (zone (car *zones-above*)))
  
  (erase)
    
  (loop for x below *width* do
       (loop for y below *height* do
            (multiple-value-bind (slid-y slid-x)
                (slide y x :focus *you*)
              (if (and (> slid-x 0) (> slid-y 0))
                  (draw-tile (aref (zonemap zone) y x)
                             slid-y slid-x)))))
  (refresh))


(defvar *controls*)

(defun read-controls-from-file ()
  (with-open-file (stream "controls.lisp" :direction :input)
    (setf *controls* (read stream))))


;; (defun illuminate2 (zm src)
;;   (let ((lx (max 0 (- (x src) (glow src))))
;;         (hx (min (1- *width*) (+ (x src) (glow src))))
;;         (ly (max 0 (- (y src) (glow src))))
;;         (hy (min (1- *height*) (+ (y src) (glow src)))))
;;     (loop for x from lx to hx do
;;          (loop for y from ly to hy do
;;               (setf (vis (aref zm y x)) 1)))))




;; =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
;; Map generation
;; =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
(defparameter *height* #x100)
(defparameter *width* #x100)

(defparameter *room-max-size* 20)
(defparameter *room-min-size* 6)
(defparameter *room-max-count* 80)

(defclass rect ()
  ((x :accessor x
      :initarg :x)
   (y :accessor y
      :initarg :y)
   (w :accessor w
      :initarg :w)
   (h :accessor h
      :initarg :h)))

(defmethod x1 ((rect rect))
  (x rect))

(defmethod x2 ((rect rect))
  (+ (x rect) (w rect)))

(defmethod y1 ((rect rect))
  (y rect))

(defmethod y2 ((rect rect))
  (+ (y rect) (h rect)))


(defmethod no-intersect-p% ((rect1 rect) (rect2 rect))
  (or (< (x2 rect1) (x1 rect2))
      (> (x1 rect1) (x2 rect2))
      (< (y2 rect1) (y1 rect2))
      (> (y1 rect1) (y2 rect2))))

  ;; (and (<= (x1 rect1) (x2 rect2))
  ;;      (<= (x1 rect2) (x2 rect1))
  ;;      (<= (y1 rect1) (y2 rect2))
  ;;      (<= (y1 rect2) (y2 rect1))))


(defmethod intersect-p ((rect1 rect) (rect2 rect))
  (not (no-intersect-p% rect1 rect2)))

(defun make-rooms (&optional (room-max-count *room-max-count*))
  (let ((rooms))
    (loop repeat room-max-count do
         (let ((w)
               (h)
               (x)
               (y)
               (room))
           (setf w (+ *room-min-size*
                      (random (- *room-max-size* *room-min-size*))))
           
           (setf h (+ *room-min-size*
                      (random (- *room-max-size* *room-min-size*))))
           (setf x (1+ (random (- *width* w 2))))
           (setf y (1+ (random (- *height* h 2))))
           (setf room (make-instance 'rect :x x :y y :w w :h h))
           (format t "W = ~d, H = ~d, X = ~d, Y = ~d~%" w h x y)
           (if (notany #'(lambda (r) (intersect-p room r)) rooms)
               (push room rooms))))
    rooms))
              
(defparameter *floortile* #\.)
(defparameter *floorcolor* :CDARK)


(defmethod midpoint ((rect rect))
  (cons (round (/ (+ (y1 rect) (y2 rect)) 2))
        (round (/ (+ (x1 rect) (x2 rect)) 2))))


(defun crooked-path (&key y1 x1 y2 x2)
  (flet ((horizontal (path direction)
           (let* ((top (car path))
                  (top-x (cdr top))
                  (top-y (car top)))
             (cons top-y
                   (+ top-x (cdr direction)))))
         (vertical (path direction)
           (let* ((top (car path))
                  (top-x (cdr top))
                  (top-y (car top)))
             (cons (+ top-y (car direction))
                   top-x))))
    (let ((direction (cons (if (< y1 y2) 1 -1)
                           (if (< x1 x2) 1 -1)))
                           
          (path (list (cons y1 x1))))
      (loop until (equalp (cons y2 x2) (car path)) do
         ;; (format t "~A~%" path)
           (cond ((= (cdr (car path)) x2)
                  ;; (print 'vert)
                  (push (vertical path direction) path))
                 ((= (car (car path)) y2)
                  ;; (print 'horiz)
                  (push (horizontal path direction) path))
                 ((= (random 2) 0)
                  ;; (print 'random-horiz)
                  (push (horizontal path direction) path))
                 (:OTHERWISE
                  ;; (print 'random-vert)
                  (push (vertical path direction) path))))
      path)))

    
  

(defun make-path (room1 room2 zone)
  ;; simple version: L shapes
  (let* ((mid1 (midpoint room1))
         (mid2 (midpoint room2))
         (startx (cdr mid1))
         (starty (car mid1))
         (endx (cdr mid2))
         (endy (car mid2))
         (path (crooked-path :y1 starty :x1 startx
                             :y2 endy :x2 endx)))
    (loop for point in path do
         (setf (aref (zonemap zone) (car point) (cdr point))
               (make-instance 'floortile)))))

(defmethod add-rooms-to-map ((zone zone))
  (loop for room in (roomlist zone) do
       (loop for x from (x1 room) to (x2 room) do
            (loop for y from (y1 room) to (y2 room) do
                 (setf (aref (zonemap zone) y x)
                       (make-instance 'floortile))))))
                                      



(defmethod scatter-special-cells ((zone zone) celltype number)
  (loop repeat number do
       (let ((y (random *height*))
             (x (random *width*)))
         (setf (aref (zonemap zone) y x)
               (make-instance celltype)))))


(defun random-walk-path (zone start-y start-x steps)
  (let ((path (list (cons start-y start-x)))
        (x start-x)
        (y start-y))
    (loop repeat steps do
         (if (zerop (random 2))
             (setf y (bound (+ start-y (pick '(1 -1))) 0 (1- *height*)))
             (setf x (bound (+ start-x (pick '(1 -1))) 0 (1- *width*))))
         (unless (block-p (aref (zonemap zone) y x))
           (setf start-x x)
           (setf start-y y)
           (push (cons y x) path)))
    path))


        
    

(defun bound (num min max)
  (cond ((< num min) min)
        ((> num max) max)
        (t num)))

(defmethod scatter-clumps ((zone zone) celltype number maxsize)
  (loop repeat number do
       (let* ((y (random *height*))
              (x (random *width*))
              (clump (random-walk-path zone y x maxsize)))
         (loop for point in clump do
              (setf (aref (zonemap zone) (car point) (cdr point))
                    (make-instance celltype))))))
         
             
         

;; === geometry stuff ===

(defun ray (y1 x1 y2 x2)
  (let* ((path (list (cons y1 x1)))
         (y-dir (if (< y1 y2) 1 -1))
         (x-dir (if (< x1 x2) 1 -1))
         (ratio (abs (if (zerop (- x1 x2))
                         1 (/ (- y1 y2) (- x1 x2)))))
         (y-step (numerator ratio))
         (x-step (denominator ratio)))
    (loop do
         (flet ((y-turn ()
                    (loop repeat (abs y-step)
                       while (/= y1 y2) do
                         (incf y1 y-dir)
                         (push (cons y1 x1) path)))
                (x-turn ()
                    (loop repeat (abs x-step)
                       while (/= x1 x2) do
                         (incf x1 x-dir)
                         (push (cons y1 x1) path))))
           (if (zerop (random 2))
               (y-turn)
               (x-turn)))
;;         (format t "[Y1: ~D, X1: ~D] [Y2: ~D, X2: ~D] y-step: ~d, x-step ~d~%" y1 x1 y2 x2 y-step x-step) ;;;;;;;;
       until (and (= x1 x2) (= y1 y2)))
    path))





(defun visible-from (subj-y subj-x obj-y obj-x)
  ;; assuming, as a simplification, that there is no glass in this
  ;; world. if we want transparent solids, we just need to add another
  ;; list like the block tiles list, and a transparent-p toplevel func
  (flet ((transparent-p (coords)
           (not (block-p (aref (zonemap (car *zones-above*))
                               (car coords) (cdr coords))))))
    (let ((line-of-sight (cdr (ray subj-y subj-x obj-y obj-x))))
      ;; (FORMAT T "Y: ~D, X: ~D~%LINE: ~A~%" subj-y subj-x line-of-sight)
      ;; (loop for coord in line-of-sight do
      ;;      (format t "~a => ~a~%" coord (transparent-p coord)))
      (every #'transparent-p line-of-sight))))

(defmethod can-see ((mob mob) y x)
  (or (and (<= (abs (- (y mob) y)) 1)
           (<= (abs (- (x mob) x)) 1))
      (and (<= (length (ray y x (y mob) (x mob)))
               (glow mob))
           (visible-from (y mob) (x mob) y x))))
        
(defun illuminate (zone src)
  (let* ((span (* 2 (glow src)))
         (lx (max 0 (- (x src) span)))
         (hx (min (1- *width*) (+ (x src) span)))
         (ly (max 0 (- (y src) span)))
         (hy (min (1- *height*) (+ (y src) span))))
    (loop for x from lx to hx do
         (loop for y from ly to hy do
              (if (can-see src y x)
                  (setf (vis (aref (zonemap zone) y x)) 1))))))

    
        
              
         

;; ==== control loop ====


(defun list-of-mobs (&optional (zm (zonemap (car *zones-above*))))
  ;; not very efficient...
  (let ((moblist))
    (loop for y below *height* do
         (loop for x below *width* do
              (if (mob (aref zm y x))
                  (push (mob (aref zm y x)) moblist))))
    moblist))

                       
                    
  

(defun update-zone (&optional (zm (zonemap (car *zones-above*))))
  (let ((moblist))
    (list-of-mobs zm)
    (loop for mob in moblist do
         (eval (action mob)))))

(defun control-loop ()
  (loop do
       (let ((move (cdr (assoc (code-char (getch)) *controls*))))
         (when move
           (eval move)
           (illuminate (car *zones-above*) *you*)
           (update-zone (zonemap (car *zones-above*)))
           (display-map)))))


;; ------------------
;; for debugging
;;-------------------

(defun generate-level (&optional (room-max-count *room-max-count*))
  (let ((newzone (make-instance 'zone)))
    (setf (roomlist newzone) (make-rooms room-max-count))
    (add-rooms-to-map newzone)
    ;;;; parameterize this stuff later
    (scatter-special-cells newzone 'rock-cell 1000)
    (scatter-clumps newzone 'water-cell 1000 50)
    ;;;;
    (loop for r on (roomlist newzone) do
         (if (cdr r)
             (make-path (car r) (cadr r) newzone)
             (make-path (car r) (car (roomlist newzone)) newzone)))
    (add-stairs 'down :zone newzone :random T)
    (setf (y *you*) (car (midpoint (car (roomlist newzone))))
          (x *you*) (cdr (midpoint (car (roomlist newzone)))))
    newzone))

(defun go-downstairs ()
  ;; STUB. We'll want to save the previous level too, of course, and
  ;; check to see if the next level has been visited before, and can
  ;; be restored, or not.
  (cond (*zones-below*
         (let ((coords))
           (push (pop *zones-below*) *zones-above*)
           (setf coords (seek-stairs 'up))
           (setf (y *you*) (car coords)
                 (x *you*) (cdr coords))))        
        (:OTHERWISE
         (push (generate-level *room-max-count*) *zones-above*)
         (add-stairs 'up :random nil :y (y *you*) :x (x *you*)))))

(defun seek-stairs (direction)
  (let ((coords))
    (loop for y below *height* do
         (loop for x below *width* do
              (when (char= (tile (aref
                                  (zonemap (car *zones-above*))
                                  y x))
                           (if (eq direction 'down) #\> #\<))
                           
                (setf coords (cons y x)))))
    coords))



(defun go-upstairs ()
  (cond ((cdr *zones-above*)
         (let ((coords))
           (push (pop *zones-above*) *zones-below*)
           (setf coords (seek-stairs 'down))
           (setf (y *you*) (car coords)
                 (x *you*) (cdr coords))
           (display-map)))
        (:OTHERWISE
         (format t "THAT'S ALL, FOLKS!~%"))))
  

(defun add-stairs (direction &key y x (random T)
                               (zone (car *zones-above*)))
  (let* ((stairroom (if random
                        (pick-a-room zone)))
         (sy (if random
                 (car (midpoint stairroom))
                 y))
         (sx (if random
                 (cdr (midpoint stairroom))
                 (1- x)))
         (cell (aref (zonemap zone) sy sx)))

    (setf (color cell) :CBROWN)
    (setf (tile cell)
          (if (eq direction 'down) #\> #\<))

    (setf (event cell) (if (eq direction 'down)
                           #'go-downstairs
                           #'go-upstairs))
    (setf (pass cell) T)
    zone))

  
(defun run ()
  (setf *zones-above* '())
  (setf *zones-below* '())
  (connect-console)
  (push (generate-level) *zones-above*)
  (display-map)
  (read-controls-from-file)
  (control-loop))


(defmethod reveal-map ((zone zone) on-off)
  ;; for debugging
  (loop for i below (* *height* *width*) do
       (setf (vis (row-major-aref (zonemap zone) i)) on-off)))
