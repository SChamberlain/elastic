elastic_env <- new.env()

#' Set connection details to an Elasticsearch engine.
#'
#' @export
#' @param host (character) The base host, defaults to `127.0.0.1`
#' @param port (character) port to connect to, defaults to `9200`
#' (optional)
#' @param path (character) context path that is appended to the end of the 
#' url. Default: `NULL`, ignored
#' @param transport_schema (character) http or https. Default: `http`
#' @param user (character) User name, if required for the connection. You 
#' can specify,  but ignored for now.
#' @param pwd (character) Password, if required for the connection. You 
#' can specify, but ignored for now.
#' @param force (logical) Force re-load of connection details. 
#' Default: `FALSE`
#' @param errors (character) One of simple (Default) or complete. Simple gives 
#' http code and  error message on an error, while complete gives both http 
#' code and error message,  and stack trace, if available.
#' @param headers Either an object of class `request` or a list that can 
#' be coerced to an object of class `request` via 
#' [httr::add_headers()]. These headers are  used in all requests. 
#' To use headers in individual requests and not others, pass in headers 
#' using [httr::add_headers()] via `...` in a function call.
#' @param cainfo (character) path to a crt bundle, passed to curl option
#' `cainfo`
#' @param ... additional curl options to be passed in ALL http requests
#' 
#' @format NULL
#' @usage NULL
#' 
#' @details The default configuration is set up for localhost access on port 
#' 9200, with no username or password.
#'
#' Running this connection method doesn't ping the ES server, but only prints 
#' your connection details.
#'
#' All connection details are stored within the returned object. We used to 
#' store them in various env vars, but are now contained within the object
#' so you can have any number of connection objects and they shouldn't 
#' conflict with one another.
#' 
#' @seealso [ping()] to check your connection
#'
#' @examples \dontrun{
#' # the default is set to 127.0.0.1 (i.e., localhost) and port 9200
#' (x <- connect())
#' x$make_url()
#' x$ping()
#' 
#' # pass connection object to function calls
#' Search(x, q = "*:*")
#'
#' # set username/password (hidden in print method)
#' connect(user = "me", pwd = "stuff")
#'  
#' # set a different host
#' # connect(host = '162.243.152.53')
#' # => http://162.243.152.53:9200
#' 
#' # set a different port
#' # connect(port = 8000)
#' # => http://localhost:8000
#' 
#' # set a different context path
#' # connect(path = 'foo_bar')
#' # => http://localhost:9200/foo_bar
#' 
#' # set to https
#' # connect(transport_schema = 'https')
#' # => https://localhost:9200
#' 
#' # set headers
#' connect(headers = list(a = 'foobar'))
#' 
#' # set cainfo path (hidden in print method)
#' connect(cainfo = '/some/path/bundle.crt')
#' }
connect <- function(host = "127.0.0.1", port = 9200, path = NULL, 
      transport_schema = "http", user = NULL, pwd = NULL, 
      headers = NULL, cainfo = NULL, force = FALSE, 
      errors = "simple", ...) {
  
  Elasticsearch$new(host = host, port = port, path = path,
      transport_schema = transport_schema, user = user, pwd = pwd, 
      headers = headers, cainfo = cainfo, force = FALSE, 
      errors = errors, ...)
}

Elasticsearch <- R6::R6Class(
  "Elasticsearch",
  public = list(
    host = NULL,
    port = NULL,
    path = NULL,
    transport_schema = NULL,
    user = NULL,
    pwd = NULL,
    headers = NULL,
    cainfo = NULL,
    force = FALSE,
    errors = "simple",
    opts = NULL,

    initialize = function(host = "127.0.0.1", port = 9200, path = NULL, 
      transport_schema = "http", user = NULL, pwd = NULL, 
      headers = NULL, cainfo = NULL, force = FALSE, errors = "simple", ...) {

      self$port <- port
      self$transport_schema <- transport_schema
      self$user <- user
      self$pwd <- pwd
      self$headers <- headers
      self$cainfo <- cainfo
      self$force <- force
      self$errors <- errors

      # strip off transport if found
      if (grepl("^http[s]?://", host)) {
        message("Found http or https on es_host, stripping off, see the docs")
        host <- sub("^http[s]?://", "", host)
      }
      self$host <- host
      
      # normalize path
      if (!is.null(path)) {
        if (grepl("/$", path)) {
          message("Normalizing path: stripping trailing slash")
          path <- sub("/$", "", path)
        }
      }
      self$path <- path

      # reset ping result in elastic_env
      elastic_env$ping_result <- NULL

      # collect curl options
      self$opts <- ec(list(cainfo = cainfo, ...))
    },

    print = function(x, ...) {
      fun <- function(x) ifelse(is.null(x) || nchar(x) == 0, 'NULL', x)
      cat('<Elasticsearch Connection>', "\n")
      cat(paste('  transport: ', fun(self$transport_schema)), "\n")
      cat(paste('  host:      ', fun(self$host)), "\n")
      cat(paste('  port:      ', fun(self$port)), "\n")
      cat(paste('  path:      ', fun(self$path)), "\n")
      cat(paste('  username:  ', fun(self$user)), "\n")
      cat(paste('  password:  ', if (!is.null(self$pwd)) "<secret>" else 'NULL' ), "\n")
      cat(paste('  errors:    ', fun(self$errors)), "\n")
      cat(paste('  headers (names): ', ph(self)), "\n")
      cat(paste('  cainfo: ', if (!is.null(self$cainfo)) "<secret>" else 'NULL'), "\n")
    },

    make_url = function(x) {
      url <- sprintf("%s://%s", self$transport_schema, self$host)
      url <- if (is.null(self$port) || nchar(self$port) == 0) {
        url
      } else {
        paste(url, ":", self$port, sep = "")
      }
      if (!is.null(self$path) && nchar(self$path) > 0) {
        url <- file.path(url, self$path)
      }
      url
    },

    ping = function(...) es_GET_(self, self$make_url(), ...),

    info = function(...) {
      res <- tryCatch(GET(self$make_url(), make_up(), ...), error = function(e) e)
      if (inherits(res, "error")) {
        stop(sprintf("\n  Failed to connect to %s\n  Remember to start Elasticsearch before connecting", 
                     make_url(es_get_auth())), call. = FALSE)
      }
      if (res$status_code > 200) {
        stop(sprintf("Error:", res$headers$statusmessage), call. = FALSE)
      }
      tt <- cont_utf8(res)
      jsonlite::fromJSON(tt, FALSE)
    },

    es_ver = function() {
      pinged <- elastic_env$ping_result
      if (is.null(pinged)) {
        elastic_env$ping_result <- pinged <- self$ping()
      }
      ver <- pinged$version$number
      
      # get only 1st 3 digits, so major:minor:patch
      as.numeric(
        paste(
          stats::na.omit(
            extractr(ver, "[[:digit:]]+")[[1]][1:3]
          ), 
          collapse = ""
        )
      )
    },

    stop_es_version = function(ver_check, fxn) {
      if (self$es_ver() < ver_check) {
        stop(fxn, " is not available for this Elasticsearch version", 
             call. = FALSE)
      }
    },

    make_conn = function(url, headers = list(), ...) {
      crul::HttpClient$new(
        url = url, 
        headers = c(self$headers, headers),
        opts = c(self$opts, ...), 
        auth = crul::auth(self$user, self$pwd)
      )
    }
  ),

  private = list()
)

es_auth <- function(es_host = NULL, es_port = NULL, es_path = NULL, 
                    es_transport_schema = NULL, es_user = NULL, es_pwd = NULL, 
                    force = FALSE, es_base = NULL) {
  
  host <- ifnull(es_host, 'ES_HOST')
  port <- if (is.null(es_port)) "" else es_port
  path <- ifnull(es_path, 'ES_PATH')
  transport <- ifnull(es_transport_schema, 'ES_TRANSPORT_SCHEMA')
  user <- ifnull(es_user, 'ES_USER')
  pwd <- ifnull(es_pwd, 'ES_PWD')

  if (identical(host, "") || force) {
    if (!interactive()) {
      stop("Please set env var ES_HOST for your host url for your Elasticsearch server",
           call. = FALSE)
    }
    message("Couldn't find env var ES_HOST See ?es_auth for more details.")
    message("Please enter your Elasticsearch host url and press enter:")
    host <- readline(": ")
    if (identical(host, "")) {
      stop("Elasticsearch host url entry failed", call. = FALSE)
    }
    message("Updating ES_HOST env var\n")
    Sys.setenv(ES_HOST = host)
  } else { 
    host <- host 
  }

  # Sys.setenv(ES_HOST = host)
  # Sys.setenv(ES_TRANSPORT = transport)
  # Sys.setenv(ES_PORT = port)
  # Sys.setenv(ES_PATH = path)
  # Sys.setenv(ES_USER = user)
  # Sys.setenv(ES_PWD = pwd)
  list(host = host, port = port, path = path, transport = transport)
}