FROM rocker/shiny-verse:latest

WORKDIR /code

# Install stable packages from CRAN
RUN install2.r --error \
    ggExtra \
    shiny

# Install Rust for tok

RUN apt-get -y update && \
  apt-get -y install curl && \
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -y

# Install development packages from GitHub
ENV TORCH_INSTALL=1 
RUN installGithub.r \
    rstudio/bslib \
    rstudio/httpuv \
    mlverse/tok
    
RUN installGithub.r \
    mlverse/minhub

COPY . .

CMD ["R", "--quiet", "-e", "shiny::runApp(host='0.0.0.0', port=7860)"]
