% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/ping.r
\name{ping}
\alias{ping}
\title{Ping an Elasticsearch server.}
\usage{
ping(conn, ...)
}
\arguments{
\item{conn}{an Elasticsearch connection object, see \code{\link[=connect]{connect()}}}

\item{...}{Curl args passed on to \link[crul:verb-GET]{crul::verb-GET}}
}
\description{
Ping an Elasticsearch server.
}
\examples{
\dontrun{
x <- connect()
ping(x)
# ideally call ping on the connetion object itself
x$ping()
}
}
\seealso{
\code{\link[=connect]{connect()}}
}
