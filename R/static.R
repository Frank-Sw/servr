#' Serve static files under a directory
#'
#' If there is an \file{index.html} under this directory, it will be displayed;
#' otherwise the list of files is displayed, with links on their names. After we
#' run this function, we can go to \samp{http://localhost:port} to browse the
#' web pages either created from R or read from HTML files.
#'
#' \code{httd()} is a pure static server, and \code{httw()} is similar but
#' watches for changes under the directory: if an HTML file is being viewed in
#' the browser, and any files are modified under the directory, the HTML page
#' will be automatically refreshed.
#' @inheritParams server_config
#' @param ... server configurations passed to \code{\link{server_config}()}
#' @export
#' @references \url{https://github.com/yihui/servr}
#' @examples #' see https://github.com/yihui/servr for command line usage
#' # or run inside an R session
#' if (interactive()) servr::httd()
httd = function(dir = '.', ...) {
  dir = normalizePath(dir, mustWork = TRUE)
  if (dir != '.') {
    owd = setwd(dir); on.exit(setwd(owd))
  }
  res = server_config(dir, ...)
  app = list(call = serve_dir(dir))
  res$start_server(app)
}

#' @param watch a directory under which \code{httw()} is to watch for changes;
#'   if it is a relative path, it is relative to the \code{dir} argument
#' @param pattern a regular expression passed to \code{\link{list.files}()} to
#'   determine the files to watch
#' @param all_files whether to watch all files including the hidden files
#' @param handler a function to be called every time any files are changed or
#'   added under the directory; its argument is a character vector of the
#'   filenames of the files modified or added
#' @rdname httd
#' @export
httw = function(
  dir = '.', watch = '.', pattern = NULL, all_files = FALSE, handler = NULL, ...
) {
  dynamic_site(dir, ..., build = watch_dir(
    watch, pattern = pattern, all_files = all_files, handler = handler
  ))
}

watch_dir = function(dir = '.', pattern = NULL, all_files = FALSE, handler = NULL) {
  cwd = getwd()
  mtime = function(dir) {
    owd = setwd(cwd); on.exit(setwd(owd), add = TRUE)
    info = file.info(list.files(
      dir, pattern, all.files = all_files, full.names = TRUE, recursive = TRUE,
      no.. = TRUE
    ))[, 'mtime', drop = FALSE]
    rownames(info) = gsub('^[.]/', '', rownames(info))
    info
  }
  info = mtime(dir)
  function(...) {
    info2 = mtime(dir)
    changed = !identical(info, info2)
    if (changed) {
      if (is.function(handler)) {
        f1 = rownames(info)
        f2 = rownames(info2)
        f3 = setdiff(f2, f1)    # new files
        f4 = intersect(f1, f2)  # old files
        f5 = f4[info[f4, 1] != info2[f4, 1]]  # modified files
        handler(c(f3, na.omit(f5)))
        info2 = mtime(dir)
      }
      info <<- info2
    }
    changed
  }
}

#' Server configurations
#'
#' The server functions in this package are configured through this function.
#' @param dir The root directory to serve.
#' @param port The TCP port number. If it is not explicitly set, the default
#'   value will be looked up in this order: First, the command line argument of
#'   the form \code{-pNNNN} (N is a digit from 0 to 9). If it was passed to R
#'   when R was started, \code{NNNN} will be used as the port number. Second,
#'   the environment variable \code{R_SERVR_PORT}. Third, the global option
#'   \code{servr.port} (e.g., \code{options(servr.port = 4322)}). If none of
#'   these command-line arguments, variables, or options were set, the default
#'   port will be \code{4321}. If this port is not available, a random available
#'   port will be used.
#' @param browser Whether to launch the default web browser. By default, it is
#'   \code{TRUE} if the R session is \code{\link{interactive}()}, or when a
#'   command line argument \code{-b} was passed to R (see
#'   \code{\link{commandArgs}()}). N.B. the RStudio viewer is used as the web
#'   browser if available.
#' @param daemon Whether to launch a daemonized server (the server does not
#'   block the current R session) or a blocking server. By default, it is the
#'   global option \code{getOption('servr.daemon')} (e.g., you can set
#'   \code{options(servr.daemon = TRUE)}); if this option was not set,
#'   \code{daemon = TRUE} if a command line argument \code{-d} was passed to R
#'   (through \command{Rscript}), or the server is running in an interactive R
#'   session.
#' @param interval The time interval used to check if an HTML page needs to be
#'   rebuilt (by default, it is checked every second). At the moment, the
#'   smallest possible \code{interval} is set to be 1, and this may change in
#'   the future.
#' @param baseurl The base URL (the full URL will be
#'   \code{http://host:port/baseurl}).
#' @param initpath The initial path in the URL (e.g. you can open a specific
#'   HTML file initially).
#' @inheritParams httpuv::startServer
#' @export
#' @return A list of configuration information of the form \code{list(host,
#'   port, start_server = function(app) {}, ...)}.
server_config = function(
  dir = '.', host = '127.0.0.1', port, browser, daemon, interval = 1, baseurl = '',
  initpath = ''
) {
  cargs = commandArgs(TRUE)
  if (missing(browser)) browser = interactive() || '-b' %in% cargs || is_rstudio()
  if (missing(port)) port = if (length(port <- grep('^-p[0-9]{4,}$', cargs, value = TRUE)) == 1) {
    sub('^-p', '', port)
  } else {
    Sys.getenv('R_SERVR_PORT', getOption('servr.port', random_port()))
  }
  port = as.integer(port)
  if (missing(daemon)) daemon = getOption('servr.daemon', ('-d' %in% cargs) || interactive())
  # rstudio viewer cannot display a page served at 0.0.0.0; use 127.0.0.1 instead
  url = sprintf(
    'http://%s:%d', if (host == '0.0.0.0' && is_rstudio()) '127.0.0.1' else host, port
  )
  if (baseurl != '') url = paste(url, baseurl, sep = '')
  url = paste0(url, if (initpath != '' && !grepl('^/', initpath)) '/', initpath)
  browsed = FALSE
  servrEnv$browse = browse = function(reopen = FALSE) {
    if (browsed && !reopen) return(invisible(url))
    if (browser || reopen) browseURL(url, browser = get_browser())
    browsed <<- TRUE
    if (!reopen) message('Serving the directory ', dir, ' at ', url)
  }
  list(
    host = host, port = port, interval = interval, url = url,
    start_server = function(app) {
      id = startServer(host, port, app)
      if (daemon) daemon_hint(id); browse()
      if (!daemon) while (TRUE) {
        httpuv::service(); Sys.sleep(0.001)
      }
      invisible(id)
    },
    browse = browse
  )
}

serve_dir = function(dir = '.') function(req) {
  owd = setwd(dir); on.exit(setwd(owd))
  path = decode_path(req)
  status = 200L

  if (grepl('^/', path)) {
    path = paste('.', path, sep = '')  # the requested file
  } else if (path == '') path = '.'
  body = if (file_test('-d', path)) {
    # ensure a trailing slash if the requested dir does not have one
    if (path != '.' && !grepl('/$', path)) return(list(
      status = 301L, body = '', headers = list(
        'Location' = sprintf('%s/', req$PATH_INFO)
      )
    ))
    type = 'text/html'
    if (file.exists(idx <- file.path(path, 'index.html'))) {
      readLines(idx, warn = FALSE)
    } else {
      d = file.info(list.files(path, all.files = TRUE, full.names = TRUE))
      title = escape_html(path)
      html_doc(c(sprintf('<h1>Index of %s</h1>', title), fileinfo_table(d)),
               title = title)
    }
  } else {
    # use the custom 404.html only if the path looks like a directory or .html
    try_404 = function(path) {
      file.exists('404.html') && grepl('(/|[.]html)$', path, ignore.case = TRUE)
    }
    # FIXME: using 302 here because 404.html may contain relative paths, e.g. if
    # /foo/bar/hi.html gives 404, I cannot just read 404.html and display it,
    # because it will be treated as /foo/bar/404.html; if 404.html contains
    # paths like ./css/style.css, I don't know how to let the browser know that
    # it means /css/style.css instead of /foo/bar/css/style.css
    if (!file.exists(path))
      return(if (try_404(path)) list(
        status = 302L, body = '', headers = list('Location' = '/404.html')
      ) else list(
        status = 404L, headers = list('Content-Type' = 'text/plain'),
        body = paste2('Not found:', path)
      ))

    type = guess_type(path)
    range = req$HTTP_RANGE

    # Chrome sends the range reuest 'bytes=0-' and I'm not sure what to do:
    # http://stackoverflow.com/a/18745164/559676
    if (is.null(range) || identical(range, 'bytes=0-')) read_raw(path) else {
      range = strsplit(range, split = "(=|-)")[[1]]
      b2 = as.numeric(range[2])
      b3 = as.numeric(range[3])

      if (length(range) < 3 || (range[1] != "bytes") || (b2 >= b3) || (b3 == 0))
        return(list(
          status = 416L, headers = list('Content-Type' = 'text/plain'),
          body = 'Requested range not satisfiable\r\n'
        ))

      status = 206L  # partial content

      con = file(path, open = "rb", raw = TRUE)
      on.exit(close(con))
      seek(con, where = b2, origin = "start")
      readBin(con, 'raw', b3 - b2 + 1)
    }
  }
  if (is.character(body) && length(body) > 1) body = paste2(body)
  list(
    status = status, body = body,
    headers = c(list('Content-Type' = type), if (status == 206L) list(
      'Content-Range' = paste(sub('=', ' ', req$HTTP_RANGE), file_size(path), sep = '/')
    ))
  )
}
