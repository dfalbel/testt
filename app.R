library(shiny)
library(bslib)
library(minhub)
library(magrittr)
source("model-session.R")

repo <- "stabilityai/stablelm-tuned-alpha-3b"
#repo <- "EleutherAI/pythia-70m"
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
    actionButton("send", "Loading model...", width = "100%")
  )
)

server <- function(input, output, session) {
  prompt <- reactiveVal(value = system_prompt)
  n_tokens <- reactiveVal(value = 0)
  
  observeEvent(input$send, {
    if (is.null(input$prompt) || input$prompt == "") {
      return()
    }
    shinyjs::disable("send")
    updateActionButton(inputId = "send", label = "Waiting for model...")
    insert_message(as.character(glue::glue("🤗: {input$prompt}")))  
    
    # we modify the prompt to trigger the 'next_token' reactive
    prompt(paste0(prompt(), "<|USER|>", input$prompt, "<|ASSISTANT|>")) 
  })
  
  next_token <- eventReactive(prompt(), ignoreInit = TRUE, {
    prompt() %>% 
      sess$generate() %>% 
      promises::then(
        onFulfilled = function(x) {x},
        onRejected = function(x) {
          insert_message(paste0("😭 Error generating token.", as.character(x)))
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
        insert_message(paste0("🤖: ", tok), append = FALSE)
      } else {
        insert_message(tok, append = TRUE)
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
  
  # Observer used at app startup time to allow using the 'Send' button once the
  # model has been loaded.
  observe({
    if (!is.null(sess$is_loaded) && sess$is_loaded) return()
    if (is.null(sess$is_loaded)) {
      cat("Started loading model ....", "\n")
      model_loaded <- sess$load_model(repo)
    }
    
    cat("Loading model:",sess$sess$poll_process(), "\n")
    invalidateLater(5000, session)
    model_loaded <- model_loaded %>% 
      promises::then(onFulfilled = function(x) {
        shinyjs::enable("send")
        updateActionButton(inputId = "send", label = "Send")
        sess$is_loaded <- TRUE
      }, onRejected = function(x) {
        shinyjs::disable("send")
        insert_message(paste0("😭 Error loading the model:\n", as.character(x)))
        sess$is_loaded <- NULL # means failure!
        sess$sess <- NULL
      })
    
    NULL # we return NULL so we don't stuck waiting for the above.
  })
}

message_id <- 0
insert_message <- function(msg, append = FALSE) {
  if (!append) {
    id <- message_id <<- message_id + 1
    insertUI(
      "#messages", 
      "beforeEnd", 
      immediate = TRUE,
      ui = card(card_body(p(id = paste0("msg-",id), msg)), style="margin-bottom:5px;")
    )
  } else {
    id <- message_id
    shinyjs::runjs(glue::glue(
      "document.getElementById('msg-{id}').textContent += '{msg}'"
    ))
  }
  # scroll to bottom
  shinyjs::runjs("var elem = document.getElementById('messages'); elem.scrollTop = elem.scrollHeight;")
}


shinyApp(ui, server)
