
# Small utility class that wraps a `callr::r_session` to return promises when
# executing `sess$call()`.
# Only one promise is resolve per time in fifo way.
promise_session <- R6::R6Class(
  lock_objects = FALSE,
  public = list(
    initialize = function() {
      self$sess <- callr::r_session$new()
      self$is_running <- FALSE
    },
    call = function(func, args = list()) {
      self$poll_process()
      promises::promise(function(resolve, reject) {
        self$push_task(func, args, resolve, reject)
        later::later(self$poll_process, 1)
      })
    },
    push_task = function(func, args, resolve, reject) {
      self$tasks[[length(self$tasks) + 1]] <- list(
        func = func, 
        args = args, 
        resolve = resolve, 
        reject = reject
      )
      cat("task pushed, now we have ", length(self$tasks), " on queue\n")
      self$run_task()
      invisible(NULL)
    },
    run_task = function() {
      if (self$is_running) return(NULL)
      if (length(self$tasks) == 0) return(NULL)
      
      self$is_running <- TRUE
      task <- self$tasks[[1]]
      self$sess$call(task$func, args = task$args)
    },
    resolve_task = function() {
      out <- self$sess$read()
      if (!is.null(out$error)) {
        self$tasks[[1]]$reject(out$error)
      } else {
        self$tasks[[1]]$resolve(out$result)
      }
      
      self$tasks <- self$tasks[-1]
      self$is_running <- FALSE
      
      self$run_task()
    },
    poll_process = function(timeout = 1) {
      if (!self$is_running) return("ready")
      poll_state <- self$sess$poll_process(timeout)
      if (poll_state == "ready") {
        self$resolve_task()
      }
      poll_state
    }
  )
)

# sess <- promise_session$new()
# f <- sess$call(function(a) {
#   10 + 1
# }, list(1))
# sess$poll_process()

