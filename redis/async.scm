;;; -*- mode: scheme; coding: utf-8 -*-
;;;
;;; Asynchronous interface
;;;

(define-module redis.async
  (extend redis.connection)
  (use redis.protocol)
  (use util.queue)
  (use gauche.threads)
  (export-all))
(select-module redis.async)


(define-class <redis-async-connection> ()
  ((conn :init-keyword :conn)
   (send-queue :init-keyword :send-queue)
   (recv-queue :init-keyword :recv-queue)
   (hndl-queue :init-keyword :hndl-queue)))

(define (redis-open-async . args)
  (let* ((conn (apply redis-open args))
         (redis (make <redis-async-connection>
                  :conn conn
                  :send-queue (make-mtqueue)
                  :recv-queue (make-mtqueue)
                  :hndl-queue (make-queue))))
    (start-threads! redis)
    redis
    ))

;;;;;;;;;;;;;;

(define-module redis._internal
  (use srfi-11)
  (define (split-args args)
    (if (symbol? args)
        (values '() args)
        (let loop ((head '())
                   (tail args))
          (if (pair? tail)
              (loop (cons (car tail) head) (cdr tail))
              (values (reverse! head) tail)))))
  (define (make-redis-command-definition command-name args)
    (let*-values (((head tail) (split-args args))
                  ((command-name) (if (list? command-name)
                                      command-name
                                      (list command-name)))
                  ((command-syms) (map (^s `(quote ,s)) command-name))
                  ((command-name) (string-join (map symbol->string command-name) "-")))
      `(define-method ,(string->symbol #`"redis-async-,|command-name|")
         ((redis <redis-async-connection>) ,@args)
         (apply redis-command redis ,@command-syms ,@head ,tail))))
  (export-all))

(import redis._internal)

(define-macro define-redis-command make-redis-command-definition)
(define-macro (define-redis-commands . command-specs)
  `(begin ,@(map (lambda (args) (apply make-redis-command-definition args)) command-specs)))

;; Talk with Redis asynchronously
(define-method redis-command ((redis <redis-async-connection>) cmd . args)
  (enqueue/wait! (ref redis 'send-queue) `(,cmd . ,args))
  (lambda (proc)
    (enqueue! (ref redis 'hndl-queue) proc)))

(define-method start-threads! ((redis <redis-async-connection>))
  ;; send-thread
  (thread-start!
   (make-thread
    (lambda ()
      (let loop ()
        (apply unified-request (ref (ref redis 'conn) 'out)
               (dequeue/wait! (ref redis 'send-queue)))
        (loop)))))

  ;; recv-thread
  (thread-start!
   (make-thread
    (lambda ()
        (let loop ()
          (enqueue/wait! (ref redis 'recv-queue)
                         (parse-reply (ref (ref redis 'conn) 'in)))
          (loop)))))
  )

;; Run on main thread
(define-method redis-async-update! ((redis <redis-async-connection>))
  (until (queue-empty? (ref redis 'recv-queue))
    ((dequeue! (ref redis 'hndl-queue)) (dequeue! (ref redis 'recv-queue)))))

;; !!Experimental
(define-method redis-async-wait-for-publish! ((redis <redis-async-connection>))
  (lambda (proc) (enqueue! (ref redis 'hndl-queue) proc)))

;; Redis Commands
(define-redis-commands
  (append (key value))
  (auth (password))
  (bgrewriteof ())
  (bgsave ())
  (blpop (key . args))
  (brpop (key . args))
  (brpoplpush (src dest timeout))
  ((config get) (param))
  ((config set) (param value))
  (dbsize ())
  ((debug object) (key))
  ((debug segfault) ())
  (decr (key))
  (decrby (key decrement))
  (del (key . args))
  (discard ())
  (dump (key))
  (echo (msg))
  (eval (script numkeys key . args))
  (exec ())
  (exists (key))
  (expire (key secs))
  (expireat (key timestamp))
  (flushall ())
  (flushdb ())
  (get (key))
  (getbit (key offset))
  (getrange (key start end))
  (getset (key value))
  (hdel (key field . fields))
  (hexists (key field))
  (hget (key field))
  (hgetall (key))
  (hincrby (key field increment))
  (hincrbyfloat (key field increment))
  (hkeys (key))
  (hlen (key))
  (hmget (key field . fields))
  (hmset (key field value . args))
  (hset (key field value))
  (hsetnx (key field value))
  (hvals (key))
  (incr (key))
  (incrby (key increment))
  (incrbyfloat (key increment))
  (info ())
  (keys (pattern))
  (lastsave ())
  (lindex (key index))
  (linsert (key pos pivot value))
  (llen (key))
  (lpop (key))
  (lpush (key value . values))
  (lpushx (key value . values))
  (lrange (key start stop))
  (lrem (key count value))
  (lset (key index value))
  (ltrim (key start stop))
  (mget (key . keys))
  (migrate (host port key destdb timeout))
  (monitor ())
  (move (key db))
  (mset (key value . args))
  (msetnx (key value . args))
  (multi ())
  ((object refcount) (key))
  ((object encoding) (key))
  ((object idletime) (key))
  (persist (key))
  (pexpire (key msecs))
  (pexpireat (key msec-timestamp))
  (ping ())
  (psetex (key msecs value))
  (psubscribe (pattern . patterns))
  (pttl (key))
  (publish (channel msg))
  (punsubscribe (pattern . patterns))
  (quit ())
  (randomkey ())
  (rename (key newkey))
  (renamenx (key newkey))
  (restore (key ttl serialized-value))
  (rpop (key))
  (rpoplpush (src dest))
  (rpush (key value . values))
  (rpushx (key value))
  (sadd (key member . members))
  (save ())
  (scard (key))
  ((script exists) (script . scripts))
  ((script flush) ())
  ((script kill) ())
  ((script load) (script))
  (sdiff (key . keys))
  (sdiffstore (dest key . keys))
  (select (index))
  (set (key value))
  (setbit (key offset value))
  (setex (key secs value))
  (setnx (key value))
  (setrange (key offset value))
  (shutdown args)
  (sinter (key . keys))
  (sinterstore (dest key . keys))
  (sismember (key member))
  (slaveof (host port))
  ((slowlog get) (count))
  ((slowlog len) ())
  ((slowlog reset) ())
  (smembers (key))
  (smove (src dest member))
  (sort (key . args))
  (spop (key))
  (srandmember (key))
  (srem (key member . members))
  (strlen (key))
  (subscribe (channel . channels))
  (sunion (key . keys))
  (sunionstore (dest key . keys))
  (sync ())
  (time ())
  (ttl (key))
  (type (key))
  (unsubscribe (channel . channels))
  (unwatch ())
  (watch (key . keys))
  (zadd (key store member . args))
  (zcard (key))
  (zcount (key min max))
  (zincrby (key increment member))
  (zinterstore (dest numkeys key . keys))
  (zrange (key start stop . args))
  (zrangebyscore (key min max . args))
  (zrank (key member))
  (zrem (key member . members))
  (zremrangebyrank (key start stop))
  (zremrangebyscore (key min max))
  (zrevrange (key start stop . args))
  (zrevrangebyscore (key max min . args))
  (zrevrank (key master))
  (zscore (key member))
  (zunionstore (dest numkeys key . keys))
  )

;;
;; Transactional Block
;;
#;(define (redis-multi-exec redis proc . keys)
  (unless (null? keys) (apply redis-watch redis keys))
  (guard (e (else
             (redis-discard redis)
             (raise e)))
    (redis-multi redis)
    (proc redis)
    (redis-exec redis)))
