source("promise-session.R")

# A wrapper a around the promise session that controls model loading and
# querying given a prompt
model_session <- R6::R6Class(
  lock_objects = FALSE,
  public = list(
    initialize = function() {
      self$sess <- promise_session$new()
      self$temperature <- 1
      self$top_k <- 50
    },
    load_model = function(repo) {
      self$sess$call(args = list(repo = repo), function(repo) {
        library(torch)
        library(zeallot)
        library(minhub)
        model <<- minhub::gptneox_from_pretrained(repo)
        model$eval()
        model$to(dtype = torch_float())
        tok <<- tok::tokenizer$from_pretrained(repo)
        "done"
      })
    },
    generate = function(prompt) {
      args <- list(
        prompt = prompt, 
        temperature = self$temperature,
        top_k = self$top_k
      )
      self$sess$call(args = args, function(prompt, temperature, top_k) {
        idx <- torch_tensor(tok$encode(prompt)$ids)$view(c(1, -1))
        with_no_grad({
          logits <- model(idx + 1L)
        })
        logits <- logits[,-1,]/temperature
        c(prob, ind) %<-% logits$topk(top_k)
        logits <- torch_full_like(logits, -Inf)$scatter_(-1, ind, prob)
        logits <- nnf_softmax(logits, dim = -1)
        id_next <- torch::torch_multinomial(logits, num_samples = 1) - 1L
        tok$decode(as.integer(id_next))  
      })
    }
  )
)
