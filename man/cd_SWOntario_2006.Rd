% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/data.R
\docType{data}
\name{cd_SWOntario_2006}
\alias{cd_SWOntario_2006}
\title{Example Dataset: South-Western Ontario Census Division Polygons}
\format{The format is formal class 'SpatialPolygonsDataFrame' [package "sp"].}
\source{
Statistics Canada (\url{http://www12.statcan.gc.ca/census-recensement/2011/geo/bound-limit/files-fichiers/gcd_000b06a_e.zip})
}
\usage{
cd_SWOntario_2006
}
\description{
An object of class 'SpatialPolygonsDataFrame' created from subsetting
a shapefile of Canadian census division boundaries. There are 39 census divisions.
}
\note{
The geometries are simplified using \code{gSimplify} [package "rgeos"],
and with polygon holes removed.
}
\keyword{datasets}
