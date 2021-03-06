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
#' @param warn (logical) whether to throw warnings from the Elasticsearch
#' server when provided. Pulls warnings from response headers when given.
#' default: `TRUE`. To turn these off, you can set `warn=FALSE` or
#' wrap function calls in [suppressWarnings()]. You can also see warnings in
#' headers by using curl verbose.
#' @param headers named list of headers. These headers are used in all requests
#' @param cainfo (character) path to a crt bundle, passed to curl option
#' `cainfo`
#' @param ignore_version (logical) ignore Elasticsearch version checks?
#' default: `FALSE`. Setting this to `TRUE` may cause some problems, it 
#' has not been fully tested yet. You may want to set this to `TRUE` if
#' it's not possible to ping the root route of the Elasticsearch instance,
#' which has the Elasticsearch version. We use the version to do
#' alter what request is sent as different Elasticsearch versions allow
#' different parameters.
#' @param ... additional curl options to be passed in ALL http requests
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
#' @section What is the connection object?:
#' Creating a connection object with `connect()` does not create
#' a DBI-like connection object. DBI-like objects have externalptr, etc.,
#' while `connect()` simply holds details about your Elasticsearch
#' instance (host, port, authentication, etc.) that is used by other
#' methods in this package to interact with your instances' ES API.
#' `connect()` is more or less a fancy list.
#' 
#' You can connect to different Elasticsearch intances within the same
#' R session by creating a separate connection object for each instance;
#' then pass the appropriate connection object to each `elastic` method.
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
  errors = "simple", warn = TRUE, ignore_version = FALSE, ...) {

  Elasticsearch$new(host = host, port = port, path = path,
      transport_schema = transport_schema, user = user, pwd = pwd,
      headers = headers, cainfo = cainfo, force = force,
      errors = errors, warn = warn, ignore_version = ignore_version, ...)
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
    warn = TRUE,
    ignore_version = FALSE,

    initialize = function(host = "127.0.0.1", port = 9200, path = NULL,
      transport_schema = "http", user = NULL, pwd = NULL,
      headers = NULL, cainfo = NULL, force = FALSE,
      errors = "simple", warn = TRUE, ignore_version = FALSE, ...) {

      self$port <- port
      self$transport_schema <- transport_schema
      self$user <- user
      self$pwd <- pwd
      self$headers <- headers
      self$cainfo <- cainfo
      self$force <- force
      self$warn <- warn
      self$ignore_version <- ignore_version

      # validate and store user error preference
      errors <- match.arg(errors, c('simple', 'complete'))
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
      cat(paste('  ignore ES version?: ', self$ignore_version), "\n")
    },

    make_url = function() {
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

    ping = function(...) {
      if (self$ignore_version) return(message("ignore_version is set to TRUE; see ?connect"))
      es_GET_(self, self$make_url(), ...)
    },

    info = function(...) {
      cli <- crul::HttpClient$new(self$make_url(), auth = self$make_up())
      res <- tryCatch(cli$get(...), error = function(e) e)
      if (inherits(res, "error")) {
        stop(sprintf("\n  Failed to connect to %s\n  Remember to start Elasticsearch before connecting",
                     self$make_url()), call. = FALSE)
      }
      if (res$status_code > 200) {
        stop(res$response_headers$status, call. = FALSE)
      }
      tt <- res$parse("UTF-8")
      jsonlite::fromJSON(tt, FALSE)
    },

    es_ver = function() {
      pinged <- elastic_env$ping_result
      if (is.null(pinged)) {
        elastic_env$ping_result <- pinged <- self$ping()
      }
      ver <- pinged$version$number

      # get only 1st 3 digits, so major:minor:patch
      digs <- stats::na.omit(extractr(ver, "[[:digit:]]+")[[1]][1:3])
      if (length(digs) == 3) digs[3] <- extractr(digs[3], "[0-9]{1}")[[1]][1]
      as.numeric(paste(digs, collapse = ""))
    },

    stop_es_version = function(ver_check, fxn) {
      if (!self$ignore_version) {
        if (self$es_ver() < ver_check) {
          stop(fxn, " is not available for this Elasticsearch version",
               call. = FALSE)
        }
      }
    },

    make_conn = function(url, headers = list(), ...) {
      crul::HttpClient$new(
        url = url,
        headers = c(self$headers, headers),
        opts = c(self$opts, ...),
        auth = crul::auth(self$user, self$pwd)
      )
    },

    make_up = function() {
      crul::auth(self$user, self$pwd)
    }

  ),

  private = list()
)
