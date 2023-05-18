FROM rocker/shiny-verse:latest

WORKDIR /code

# Install stable packages from CRAN
RUN install2.r --error \
    ggExtra \
    shiny \
    callr

# Install Rust for tok

RUN apt-get -y update && \
  apt-get -y install curl && \
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Install development packages from GitHub
ENV TORCH_INSTALL=1 
RUN installGithub.r \
    rstudio/bslib \
    rstudio/httpuv \
    mlverse/tok
    

RUN Rscript -e "\
options(timeout = 600);\
kind <- 'cpu';\
version <- '0.10.0.9000';\
options(repos = c(\
  torch = sprintf('https://storage.googleapis.com/torch-lantern-builds/packages/%s/%s/', kind, version),\
  CRAN = 'https://cloud.r-project.org'\
));\
install.packages('torch');\
"

RUN installGithub.r \
    mlverse/minhub


ENV HUGGINGFACE_HUB_CACHE="/tmp/"
COPY . .
CMD ["R", "--quiet", "-e", "shiny::runApp(host='0.0.0.0', port=7860)"]
