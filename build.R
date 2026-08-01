# ------------------------------------------------------------------------------
# build.R — export the Shiny app to a static Shinylive site in _site/
#
# Run locally with:
#   Rscript build.R
#
# then preview with:
#   httpuv::runStaticServer("_site")     # or: python3 -m http.server -d _site
#
# The exported site is fully static: R runs in the browser under WebAssembly
# (webR), so it can be served from GitHub Pages with no server-side R.
# ------------------------------------------------------------------------------

if (!requireNamespace("shinylive", quietly = TRUE)) {
  install.packages("shinylive", repos = "https://cloud.r-project.org")
}

appdir <- "app"
outdir <- "_site"

stopifnot(file.exists(file.path(appdir, "app.R")))

# Sanity check: the model must parse and reproduce the published estimates
# before we ship a build.
source("tests/test-model.R", chdir = FALSE)

message("Exporting ", appdir, " -> ", outdir, " ...")
shinylive::export(appdir, outdir)

# Prevent GitHub Pages from running the app output through Jekyll.
file.create(file.path(outdir, ".nojekyll"))

message("Done. Site written to ", normalizePath(outdir))
message("Preview: httpuv::runStaticServer(\"", outdir, "\")")
