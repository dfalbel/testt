library(shiny)
library(bslib)
library(minhub)
library(magrittr)
source("model-session.R")

repo <- "EleutherAI/pythia-70m"
repo <- Sys.getenv("MODEL_REPO", unset = repo)
sess <- model_session$new()

max_n_tokens <- 100
system_prompt = "<|SYSTEM|># StableLM Tuned (Alpha version)
- StableLM is a helpful and harmless open-source AI language model developed by StabilityAI.
- StableLM is excited to be able to help the user, but will refuse to do anything that could be considered harmful to the user.
- StableLM is more than just an information source, StableLM is also able to write poetry, short stories, and make jokes.
- StableLM will refuse to participate in anything that could harm a human.
"

ui <- page_fillable(
  theme = bs_theme(bootswatch = "minty"),
  shinyjs::useShinyjs(),
  card(
    height="90%",
    heights_equal = "row",
    width = 1,
    fillable = FALSE,
    card_body(id = "messages", gap = 5, fillable = FALSE)
  ),
  layout_column_wrap(
    width = 1/2,
    textInput("prompt", label = NULL, width="100%"),
    actionButton("send", "Send", width = "100%")
  )
)

server <- function(input, output, session) {
  prompt <- reactiveVal(value = system_prompt)
  n_tokens <- reactiveVal(value = 0)
  msg_id <- reactiveVal(value = 0)
  
  observeEvent(input$send, {
    if (is.null(input$prompt) || input$prompt == "") {
      return()
    }
    shinyjs::disable("send")
    updateActionButton(inputId = "send", label = "Waiting for model...")
    insert_message(msg_id, as.character(glue::glue("🤗: {input$prompt}")))  
    
    # we modify the prompt to trigger the 'next_token' reactive
    prompt(paste0(prompt(), "<|USER|>", input$prompt, "<|ASSISTANT|>")) 
  })
  
  next_token <- eventReactive(prompt(), ignoreInit = TRUE, {
    prompt() %>% 
      sess$generate() %>% 
      promises::then(
        onFulfilled = function(x) {x},
        onRejected = function(x) {
          insert_message(msg_id, paste0("😭 Error generating token.", as.character(x)))
          updateActionButton(inputId = "send", label = "Failing generation. Contact admin.")
          NULL
        }
      )
  })
  
  observeEvent(next_token(), {
    tok <- next_token()
    
    n_tokens(n_tokens() + 1)
    tok %>% promises::then(function(tok) {
      if (n_tokens() == 1) {
        insert_message(msg_id, paste0("🤖: ", tok), append = FALSE)
      } else {
        insert_message(msg_id, tok, append = TRUE)
      }
      
      if (tok != "" && n_tokens() < max_n_tokens) {
        prompt(paste0(prompt(), tok))
      } else {
        shinyjs::enable("send")
        updateActionButton(inputId = "send", label = "Send")
        n_tokens(0)
      }
    })
  })
  
  observe({
    # an observer that makes sure tasks are resolved during the shiny loop
    invalidateLater(5000, session)
    if (!is.null(sess$sess))
      sess$sess$poll_process(1)
  })
  
  # Observer used at app startup time to allow using the 'Send' button once the
  # model has been loaded.
  model_loaded <- reactiveVal()
  event_reload <- reactiveVal(val = 0)
  observeEvent(event_reload(), ignoreNULL=FALSE, {
    
    # the model is already loaded, nothing to do
    if (!is.null(sess$is_loaded) && sess$is_loaded) return()
    
    # the model isn't loaded, this we disable the send button and
    # show that we are loading the model
    shinyjs::disable("send")
    updateActionButton(inputId = "send", label = "Loading the model...")
    
    # the model isn't loaded and no task is trying to load it, so we start a new
    # task to load it
    if (is.null(sess$is_loaded)) {
      cat("Started loading model ....", "\n")
      model_loaded(sess$load_model(repo))
      sess$is_loaded <- FALSE # not yet loaded, but loading
    }
    
    # this runs for the cases where sess$is_loaded was NULL or if 
    # sess$is_loaded = FALSE ie (another connection already tried)
    # to load the model.
    
    cat("Loading model:",sess$sess$poll_process(), "\n")
    m <- model_loaded() %>% 
      promises::then(onFulfilled = function(x) {
        cat("Model has been loaded!", "\n")
        shinyjs::enable("send")
        updateActionButton(inputId = "send", label = "Send")
        sess$is_loaded <- TRUE
        TRUE
      }, onRejected = function(x) {
        shinyjs::disable("send")
        insert_message(paste0("😭 Error loading the model:\n", as.character(x)))
        sess$is_loaded <- NULL # means failure!
        sess$sess <- NULL
        if (event_reload() < 10) {
          Sys.sleep(5)
          event_reload(event_reload() + 1)
        }
        FALSE
      })
    model_loaded(m)
  })
}

insert_message <- function(message_id, msg, append = FALSE) {
  if (!append) {
    id <- message_id() + 1
    message_id(id)
    
    insertUI(
      "#messages", 
      "beforeEnd", 
      immediate = TRUE,
      ui = card(style="margin-bottom:5px;", card_body(
        p(id = paste0("msg-",id), msg)
      ))
    )
  } else {
    id <- message_id()
    shinyjs::runjs(glue::glue(
      "document.getElementById('msg-{id}').textContent += '{msg}'"
    ))
  }
  # scroll to bottom
  shinyjs::runjs("var elem = document.getElementById('messages'); elem.scrollTop = elem.scrollHeight;")
  id
}


shinyApp(ui, server)
