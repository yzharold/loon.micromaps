
#' @title Linked Micromaps in loon
#'
#' @description Compares different statistics across geographical regions
#'
#' @param top Tk top level window. Defaults to a new window
#' @param mm_inspector Whether to draw custom inspector for the display, which
#'   allows for variable selection, variable label update, font size adjustment,
#'   and setting grouping of points. Defaults to TRUE. Once created, the inspector
#'   can only be closed when the main display window is closed
#' @param title Title for linked micromaps. Appears in the title bar of
#'   the toplevel window
#' @param map.label Label for maps (rightmost) panel
#' @param lab.label Label for labels (leftmost) panel
#' @param spdf \code{SpatialPolygonsDataFrame} object to hold polygon coordinates
#'   and attributes. It should contain statistics used for comparing between regions
#' @param grouping An optional character vector specifying how many points to
#'   have per row (from top to bottom of display)
#' @param n_groups An optional integer specifying how many rows to have.
#'   If both \code{grouping} and \code{n_groups} are provided, \code{grouping}
#'   is applied
#' @param variables List specifying variables to plot. Variable required: \code{id.var}
#'   and \code{grouping.var}. Optional variables: more variables to plot.
#'   \code{id.var} specifies the names of points. The \code{grouping.var} is
#'   used to decide the ordering of points on the map. All variables,
#'   with the exception of \code{id.var}, should be a list with \code{name},
#'   and optional \code{xlab} and optional \code{label} arguments.
#'   For example, for a variable named 'ed' used for grouping, the \code{variables}
#'   argument would look like:
#'   \code{variables = list(grouping.var = list(name = "ed", xlab = "Percent", label = "\% with University Education"))}
#' @param num_optvars Number of possible optional variables for \code{mm_inspector}.
#'   Defaults to NULL, in which case it is determined based on how many variables are
#'   provided to \code{variables}
#' @param spacing Spacing scheme for points - either 'equal' or 'max'. The 'equal'
#'   scheme spaces points out equally, while the 'max' scheme ensures the
#'   same amount of spacing between points as the row with the largest
#'   number of points
#' @param color Color scheme. Defaults to NULL, in which case colors are
#'   generated using \code{loon::loon_palette}. Cannot be 'cornsilk' or 'magenta',
#'   which are reserved colors
#' @param size Size of glyphs for scatterplots and label panel. Defaults to 6
#' @param linkingKey Linking mechanism in \code{loon}. Points with the same
#'   linkingKey value are linked together. Defaults to NULL, in which case the
#'   linkingKey values are index values starting from 0
#' @param linkingGroup Linking mechanism in \code{loon}. Displays with the same
#'   linkingGroup are linked together. Defaults to NULL, in which case the
#'   linkingGroup is "Micromaps"
#' @param sync Can be either 'pull' or 'push', determines whether the initial
#'   synchronization should adapt to the linked states of other linked plots ("pull")
#'   or whether it should overwrite the states of the other linked plot with its
#'   own linked states ("push")
#' @param ... Other optional named arguments to modify states of scatterplots
#'
#' @return An object of classes \code{loon_micromaps} and \code{loon}, containing
#'   the Tk toplevel window, \code{linkingGroup} value, \code{linkingKey} values,
#'   and the handles for the \code{loon} plot objects corresponding to
#'   the labels panel, scatterplot panel(s) and map panel in list form
#'
#' @export
#'
#' @import loon
#' @import tcltk
#' @import sp
#' @import grDevices
#' @import stats
#' @import utils
#' @import methods
#' @importFrom magrittr %>%
#' @importFrom dplyr arrange_ arrange select_ mutate
#'
#' @examples
#' \dontrun{
#'
#' data("USstates", package = "micromap")
#' data("edPov", package = "micromap")
#'
#' USstates@data <- merge(USstates@data, edPov, by.x = 'ST', by.y = 'StateAb')
#'
#' mm <- l_micromaps(lab.label = 'States',
#'                   spdf = USstates,
#'                   variables = list(id.var = 'ST_NAME',
#'                                    grouping.var = list(name = 'pov', xlab = 'Percent'),
#'                                    var2 = list(name = 'ed', xlab = 'Percent')),
#'                   spacing = 'max', sync = 'push',
#'                   itemLabel = as.character(USstates@data$ST_NAME),
#'                   showItemLabels = T)
#'
#' }
#'
l_micromaps <- function(top = tktoplevel(), mm_inspector = TRUE,
                        title = 'Micromaps', map.label = 'Map', lab.label = 'Labels',
                        spdf,
                        grouping = NULL, n_groups = NULL,
                        variables, num_optvars = NULL,
                        spacing = c('equal', 'max'), color = NULL, size = 6,
                        linkingKey = NULL, linkingGroup = NULL, sync = c('pull', 'push'), ...) {

  .Tcl('set ::loon::Options(printInConfigurationWarning) FALSE')

  # Input checks -----
  if (!is(top, 'tkwin'))
    stop('top should be a Tk toplevel window generated by tktoplevel()')

  if (!is.logical(mm_inspector) | length(mm_inspector) > 1)
    stop('mm_inspector should be TRUE or FALSE only')

  if (!is(spdf, 'SpatialPolygonsDataFrame'))
    stop('spdf must be of class SpatialPolygonsDataFrame')

  if (length(unique(spdf@plotOrder)) != nrow(spdf@data)) {
    stop('plotOrder for spdf does not correspond to the number of data points')
  }

  for (vars in c('map.label', 'lab.label', 'title')) {
    if (!is.character(get(vars)) | length(get(vars)) > 1 | identical(get(vars), ''))
      stop(paste0(vars, ' must be a single non-empty string'))
  }

  if (!(sync %in% c('push', 'pull'))) {
    stop('sync for linking states must be either pull or push')
  }


  if (any(c('cornsilk', 'CORNSILK', '#fff8dc', '#FFF8DC', '#FFFFF8F8DCDC', '#fffff8f8dcdc') %in% color)) {
    stop('color cannot be cornsilk, which is reserved for l_micromaps')
  }

  if (any(c('magenta', 'MAGENTA', '#ff00ff', '#FF00FF', '#FFFF0000FFFF', '#ffff0000ffff') %in% color)) {
    stop('color cannot be magenta, which is reserved for l_micromaps')
  }


  if (!is.list(variables)) stop('variables should be specified as a nested list.')


  if (!('id.var' %in% names(variables))) stop('Must specify the name of the id.var in variables as list(id.var = ...)')

  id.var <- variables$id.var
  if (!(id.var %in% names(spdf@data))) stop('id.var does not exist in spdf data')


  if (!('grouping.var' %in% names(variables))) {
    stop('Must specify the grouping.var in variables as list(grouping.var = list(name = ...))')
  }


  # Assign grouping and other variables (including type checks)
  vars <- Map(function(x, y) {
    variable_check(spdf, x, y)
  }, setdiff(names(variables), 'id.var'), variables[-which(names(variables) == 'id.var')])


  for (x in names(vars)) {

    assign(x, vars[[x]]$name)
    assign(paste0(x, '.xlab'), vars[[x]]$xlab)
    assign(paste0(x, '.label'), vars[[x]]$label)

  }

  scatterplot_vars <- names(vars)



  # Data-related -----
  n <- nrow(spdf@data)
  spdf@data$id <- 1:n
  spdf@data$NAME <- as.character(spdf@data[[id.var]])

  grouping <- allocate_group(n_groups = n_groups, grouping = grouping, n = n)
  n_groups <- length(grouping)

  group <- Map(function(x, y) {
    rep(y, times = x)
  }, grouping, 1:n_groups) %>% unlist()

  max_per_group <- max(grouping)


  color_orig <- color
  if (!is.null(color) & !is.character(color)) stop('color, if specified, should consist of character values')

  if (is.null(color)) color <- loon_palette(max(grouping))
  if (length(color) > 0) color <- rep(color, length.out = max(grouping))


  if (is.null(linkingKey)) {
    linkingKey <- paste(spdf@data$id - 1)
  }

  spdf@data$linkingKey <- linkingKey

  if (is.null(linkingGroup)) linkingGroup <- 'Micromaps'


  spdf@data <- spdf@data %>%
    arrange_(.dots = c(paste0('-', grouping.var), 'NAME')) %>%
    mutate(group = group) %>%
    arrange(id)


  plotorder_exp <- Map(function(x) {

    n <- length(spdf@polygons[[x]]@Polygons)
    rep(x, times = n)

  }, spdf@plotOrder) %>% unlist()


  xlims <- lapply(scatterplot_vars, function(v) {
    spdf@data[[get(v)]] %>% pretty() %>% extendrange()
  })


  # Additional arguments
  more_states <- list(...)

  if (length(more_states) > 0) {

    if (any(identical(names(more_states), ''))) {
      stop('... must be named arguments')
    }


    margin_states <- more_states[names(more_states) %in% c('minimumMargins', 'labelMargins', 'scalesMargins')]

    margin_states_len <- vapply(margin_states, length, FUN.VALUE = numeric(1))

    if (length(margin_states) > 0 & any(margin_states_len != 4)) {

      paste(names(margin_states_len)[margin_states_len != 4], collapse = ', ') %>%
        stop(paste0(., ' must be of length 4'))

    }


    more_states <- more_states[!(names(more_states) %in% c('minimumMargins', 'labelMargins', 'scalesMargins'))]


    more_states_len <- vapply(more_states, length, FUN.VALUE = numeric(1))

    if (any(more_states_len != 1 & more_states_len != n)) {

      paste(names(more_states)[(more_states_len != 1 & more_states_len != n)], collapse = ', ') %>%
        stop(paste0(., ' must be of length 1 or ', n))

    }

    state_orig_names <- names(more_states)

    for (k in 1:length(more_states)) {

      state_nm <- names(more_states)[k]

      if (state_nm %in% names(spdf@data)) {
        state_nm <- paste0(state_nm, 'MM')
        names(more_states)[k] <- state_nm
      }

      spdf@data[[state_nm]] <- more_states[[k]]

    }
  }



  # Set up loon
  # tt <- tktoplevel()
  tktitle(top) <- title

  p_scatterplot <- lapply(1:length(scatterplot_vars), function(v) {
    vector(length = n_groups)
  })

  p_map_base <- vector(length = n_groups)
  p_map <- vector('list', length = n_groups)

  p_label <- vector(length = n_groups)
  p_label_text <- vector(length = n_groups)


  p_scale_base <- vector(length = n_groups)
  p_scale_labs <- vector(length = n_groups)
  p_scale_ticks <- vector(length = n_groups)


  data <- vector('list', length = n_groups)
  color_df <- vector('list', length = n_groups)

  mapping_scatterplot2map <- vector('list', length = n_groups)
  mapping_map2scatterplot <- vector('list', length = n_groups)


  # Create plots -----
  for (i in 1:n_groups) {

    data[[i]] <- spdf@data[spdf@data$group == i, ] %>%
      arrange_(.dots = c(paste0('-', grouping.var), 'NAME'))

    data[[i]]$colors <- color[1:nrow(data[[i]])]


    # Apply other named arguments to scatterplots
    if (length(more_states) > 0) {

      states_i <- data[[i]][, names(more_states), drop = FALSE] %>% as.list()

      states_i <- lapply(states_i, function(x) {
        if (length(unique(x)) == 1) {
          x[1]
        } else {
          x
        }
      })

      names(states_i) <- state_orig_names

    }

    # Scatterplot(s)
    for (jj in 1:length(scatterplot_vars)) {

      var <- get(scatterplot_vars[jj])

      if (spacing == 'max') {
        y_pr <- seq(max_per_group, max_per_group - nrow(data[[i]]) + 1)
      } else {
        y_pr <- seq(grouping[i], 1)
      }


      p_scatterplot[[jj]][i] <- l_plot(parent = top,
                                       x = data[[i]][[var]],
                                       y = y_pr,
                                       color = data[[i]][['colors']],
                                       size = size,
                                       linkingKey = data[[i]][['linkingKey']],
                                       linkingGroup = linkingGroup,
                                       sync = sync)


      if (spacing == 'max') {

        l_configure(p_scatterplot[[jj]][i],
                    panY = 0, zoomY = 1, deltaY = max_per_group + 1)

      } else {

        l_configure(p_scatterplot[[jj]][i],
                    panY = 0, zoomY = 1, deltaY = grouping[i] + 1)

      }


      l_configure(p_scatterplot[[jj]][i],
                  panX = xlims[[jj]][1], zoomX = 1, deltaX = diff(xlims[[jj]]),
                  showLabels = T, xlabel = '', ylabel = '')

      if (length(more_states) > 0)  do.call('l_configure', c(p_scatterplot[[jj]][i], states_i))

      if (length(margin_states) > 0) do.call('l_configure', c(p_scatterplot[[jj]][i], margin_states))


    }



    # Maps
    p_map_base[i] <- l_plot(parent = top)

    p_map[[i]] <- l_layer(p_map_base[i], spdf,
                          color = 'cornsilk',
                          asSingleLayer = TRUE, label = paste0('map_', i))

    l_scaleto_world(p_map_base[i])


    # Get colors for polygons
    color_df[[i]] <- data.frame(key = plotorder_exp,
                                color = data[[i]]$colors[match(plotorder_exp, data[[i]]$id)],
                                stringsAsFactors = F)
    color_df[[i]]$color[is.na(color_df[[i]]$color)] <- 'cornsilk'

    l_configure(c(p_map_base[i], p_map[[i]]), color = color_df[[i]]$color)



    # Labels
    p_label[i] <- l_plot(parent = top,
                         x = rep(1, nrow(data[[i]])),
                         y = y_pr,
                         color = data[[i]][['colors']],
                         size = size,
                         linkingKey = data[[i]][['linkingKey']],
                         linkingGroup = linkingGroup,
                         sync = sync)


    if (spacing == 'max') {
      l_configure(p_label[i],
                  panY = 0, zoomY = 1, deltaY = max_per_group + 1)
    } else {
      l_configure(p_label[i],
                  panY = 0, zoomY = 1, deltaY = grouping[i] + 1)
    }


    l_configure(p_label[i], panX = 0, zoomX = 1, deltaX = 6,
                xlabel = '', ylabel = '')


    if (length(more_states) > 0) do.call('l_configure', c(p_label[i], states_i))

    if (length(margin_states) > 0) do.call('l_configure', c(p_label[i], margin_states))



    # Truncate label text if they are too long
    trunc_labels <- vapply(as.character(data[[i]]$NAME),
                           function(x) ifelse(nchar(x) > 25, paste0(substr(x, 1, 25), '...'), x),
                           FUN.VALUE = character(1), USE.NAMES = F)


    p_label_text[i] <- l_layer_texts(p_label[i],
                                     x = rep(2, nrow(data[[i]])),
                                     y = y_pr,
                                     text = trunc_labels,
                                     anchor = 'w',
                                     size = size,
                                     col = 'black')



    mapping_scatterplot2map[[i]] <- lapply(data[[i]]$NAME, function(x) which(attr(p_map[[i]], 'NAME') == x))
    names(mapping_scatterplot2map[[i]]) <- data[[i]]$NAME

    mapping_map2scatterplot[[i]] <- match(attr(p_map[[i]], 'NAME'), data[[i]]$NAME)

  }


  pr_transform <- function(x, pan, zoom, delta) {
    (x - pan)/(zoom * delta)
  }

  pr_invtransform <- function(y, pan, zoom, delta) {
    y * zoom * delta + pan
  }


  # Axis for scatterplots -----
  axis_tickpoints <- lapply(scatterplot_vars, function(v) pretty(spdf@data[[get(v)]]))


  for (kk in 1:length(scatterplot_vars)) {

    axis <- axis_tickpoints[[kk]]

    ticks_x <- Map(function(z) {
      c(axis[z], axis[z])
    }, 1:length(axis))


    ticks_y <- Map(function(z) {
      c(0.5, 0.7)
    }, 1:length(axis))


    p_scale_base[kk] <- l_plot(parent = top,
                               background = 'gray95', foreground = 'gray95',
                               showLabels = T, xlabel = '', ylabel = '',
                               minimumMargins = c(0, 20, 0, 20), showScales = F)

    p_scale_labs[kk] <- l_layer_texts(p_scale_base[kk],
                                      x = axis, y = rep(0.3, length(axis)),
                                      text = axis, color = 'black')

    p_scale_ticks[kk] <- l_layer_lines(p_scale_base[kk],
                                       x = c(list(c(xlims[[kk]][1], xlims[[kk]][2])),
                                             ticks_x),
                                       y = c(list(c(0.7, 0.7)),
                                             ticks_y))

    l_configure(p_scale_base[kk],
                panX = xlims[[kk]][1], zoomX = 1, deltaX = diff(xlims[[kk]]))

  }



  # Bindings -----

  # Zoom/pan/delta of scatterplots
  b_xmoves <- lapply(1:length(scatterplot_vars), function(v) {
    do.call('bind_zoompandelta', c(direction = 'x', as.list(c(p_scatterplot[[v]], p_scale_base[v]))))
  })


  b_ymoves <- lapply(1:n_groups, function(v) {

    scatterplots <- lapply(1:length(scatterplot_vars), function(z) p_scatterplot[[z]][v])

    do.call('bind_zoompandelta', c(direction = 'y', c(p_label[v], scatterplots)))

  })


  # Connecting scatterplot points to polygons in maps
  b_scatterplot2map_sel <- lapply(1:n_groups, function(x) {

    bind_scat2map_sel(s = p_scatterplot[[1]][x], m = p_map[[x]],
                      mapping = mapping_scatterplot2map[[x]],
                      plotorder_exp = plotorder_exp, ids = data[[x]]$id)

  })


  b_scatterplot2map_col <- lapply(1:n_groups, function(x) {
    bind_scat2map_col(s = p_scatterplot[[1]][x], m = p_map[[x]],
                      plotorder_exp = plotorder_exp, ids = data[[x]]$id)
  })


  b_map2scatterplot <- lapply(1:n_groups, function(x) {
    bind_map2scat(s = p_scatterplot[[1]][x], m = p_map[[x]], m_base = p_map_base[x],
                  mapping = mapping_map2scatterplot[[x]])
  })


  b_map2scat_add <- lapply(1:n_groups, function(x) {
    bind_map2scat_add(s = p_scatterplot[[1]][x], m = p_map[[x]], m_base = p_map_base[x],
                      mapping = mapping_map2scatterplot[[x]])
  })


  # Prevent zoom/pan in the horizontal direction for the label (leftmost) column
  b_disable <- lapply(1:n_groups, function(x) {
    disable_zoompandelta(direction = 'x', p_label[x])
  })



  # Packing -----

  # Reset grid configuration; otherwise going from 2 -> 1 scatterplot columns will still leave 4 columns overall
  old <- as.character(tkgrid.slaves(top))
  lapply(old, function(x) tkgrid.forget(x))


  # Create labels
  label_lab <- tcl('label', l_subwin(top,'label_for_labels'), text = lab.label)

  stat_labs <- lapply(1:length(scatterplot_vars), function(v) {
    var <- scatterplot_vars[v]
    tcl('label', l_subwin(top, paste0('label_for_scat_', v)), text = get(paste0(var, '.label')))
  })

  axis_labs <- lapply(1:length(scatterplot_vars), function(v) {
    var <- scatterplot_vars[v]
    tcl('label', l_subwin(top, paste0('axis_label_for_', v)), text = get(paste0(var, '.xlab')))
  })

  map_lab <- tcl('label', l_subwin(top,'label_for_maps'), text = map.label)


  # Layout
  n_row <- n_groups + 3
  n_col <- length(scatterplot_vars) + 2


  tkgrid(label_lab, row = 0, column = 0, sticky = "nesw")

  for (ii in 1:length(scatterplot_vars)) {
    tkgrid(stat_labs[[ii]], row = 0, column = ii, sticky = 'nesw')
  }

  tkgrid(map_lab, row = 0, column = n_col - 1, sticky = "nesw")


  for (ii in 1:n_groups) {

    tkgrid(p_label[ii], row = ii, column = 0, sticky = 'nesw')

    for (jj in 1:length(scatterplot_vars)) {
      tkgrid(p_scatterplot[[jj]][ii], row = ii, column = jj, sticky = 'nesw')
    }

    tkgrid(p_map_base[ii], row = ii, column = n_col - 1, sticky = 'nesw')

  }


  for (jj in 1:length(scatterplot_vars)) {

    tkgrid(p_scale_base[jj], row = n_groups + 1, column = jj, sticky = 'nesw')
    tkgrid(axis_labs[[jj]], row = n_row - 1, column = jj, sticky = 'nesw')

  }



  for (c in 0:(n_col - 1)) {
    tkgrid.columnconfigure(top, c, weight = 2)
  }


  for (r in 1:(n_row - 2)) {
    tkgrid.rowconfigure(top, r, weight = 2)
  }
  tkgrid.rowconfigure(top, n_groups + 1, weight = 3, minsize = 20)



  # Return values -----
  ret <- list(top = top,
              linkingGroup = linkingGroup,
              linkingKey = linkingKey,
              labels = list(base = p_label, text = p_label_text),
              scatterplots = p_scatterplot,
              maps = list(base = p_map_base, polygons = p_map))

  attr(ret, 'class') <- c('loon_micromaps', 'loon')


  # Inspector -----
  mmInspector <- function(w) {

    tt_inspector <- tktoplevel()
    tktitle(tt_inspector) <- 'Micromaps Inspector'


    overall <- tkframe(tt_inspector)
    labs <- tkframe(overall, borderwidth = 3)
    gr <- tkframe(overall, relief = 'groove', borderwidth = 3)
    sz <- tkframe(overall, borderwidth = 3)
    opt <- tkframe(overall, relief = 'groove', borderwidth = 3)
    final <- tkframe(overall, borderwidth = 3)


    # Label section
    lab.label_i <- tclVar(lab.label)
    entry.lab.label <- tkentry(labs, textvariable = lab.label_i, width = 20)

    map.label_i <- tclVar(map.label)
    entry.map.label <- tkentry(labs, textvariable = map.label_i, width = 20)


    tkgrid(tklabel(labs, text = 'Labels', anchor = 'e'),
           padx = 5, pady = 5, row = 0, columnspan = 4, sticky = 'w')

    tkgrid(tklabel(labs, text = 'Point label: ', anchor = 'w'),
           tklabel(labs, text = 'Map label: ', anchor = 'w'),
           sticky = 'w', padx = 5, pady = 5, row = 1)

    tkgrid(entry.lab.label,
           entry.map.label,
           sticky = 'w', padx = 5, pady = 5, row = 2)


    # Grouping section
    vars <- setdiff(names(spdf@data)[sapply(spdf@data, is.numeric)],
                    c('id', 'name', 'NAME', 'group', 'linkingKey'))


    grouping.var_i <- tclVar(grouping.var)
    box.grouping.var <- ttkcombobox(gr, values = vars,
                                    textvariable = grouping.var_i,
                                    state = 'readonly')
    grouping.var.xlab_i <- tclVar(grouping.var.xlab)
    entry.grouping.var.xlab <- tkentry(gr, textvariable = grouping.var.xlab_i, width = 20)
    grouping.var.label_i <- tclVar(grouping.var.label)
    entry.grouping.var.label <- tkentry(gr, textvariable = grouping.var.label_i, width = 20)


    n_groups_i <- tclVar(ifelse(is.null(n_groups), '', as.character(n_groups)))
    entry.n_groups <- tkentry(gr, textvariable = n_groups_i, width = 20)

    grouping_char <- paste0(grouping, collapse = ',')
    grouping_i <- tclVar(ifelse(is.null(grouping), '', grouping_char))
    entry.grouping <- tkentry(gr, textvariable = grouping_i, width = 20)


    tkgrid(tklabel(gr, text = 'Grouping', anchor = 'e'),
           padx = 5, pady = 5, row = 0, columnspan = 4, sticky = 'w')

    tkgrid(tklabel(gr, text = 'Grouping variable: ', anchor = 'w'),
           tklabel(gr, text = 'Axis label: ', anchor = 'w'),
           tklabel(gr, text = 'Plot label: ', anchor = 'w'),
           sticky = 'w', padx = 5, pady = 5, row = 1)

    tkgrid(box.grouping.var,
           entry.grouping.var.xlab,
           entry.grouping.var.label,
           sticky = 'w', padx = 5, pady = 5, row = 2)

    tkgrid(tklabel(gr, text = 'Number of groups: ', anchor = 'w'),
           tklabel(gr, text = 'Grouping: ', anchor = 'w'),
           sticky = 'w', padx = 5, pady = 5, row = 3)

    tkgrid(entry.n_groups, entry.grouping,
           sticky = 'w', padx = 5, pady = 5, row = 4)


    # Font size
    currSize <- tclVar(as.character(size))
    size_disp <- tklabel(sz, textvariable = currSize)

    minus <- tkbutton(sz, text = '-', command = function() downsize())
    plus <- tkbutton(sz, text = '+', command = function() upsize())


    tkgrid(tklabel(sz, text = 'Fontsize: ', anchor = 'w'),
           minus, plus, size_disp)


    # Optional variables
    num_vars <- max(1, length(p_scatterplot) - 1, num_optvars)


    var_i <- vector('list', length = num_vars)
    box.var <- vector('list', length = num_vars)
    var.xlab_i <- vector('list', length = num_vars)
    entry.var.xlab <- vector('list', length = num_vars)
    var.label_i <- vector('list', length = num_vars)
    entry.var.label <- vector('list', length = num_vars)

    for (i in 1:num_vars) {

      varname <- setdiff(names(variables), c('id.var', 'grouping.var'))[i]

      var_i[[i]] <- tclVar(ifelse(is.na(varname), 'N/A', get(varname)))
      box.var[[i]] <- ttkcombobox(opt, values = c('N/A', vars),
                                  textvariable = var_i[[i]],
                                  state = 'readonly')

      var.xlab_i[[i]] <- tclVar(ifelse(is.na(varname), '', get(paste0(varname, '.xlab'))))
      entry.var.xlab[[i]] <- tkentry(opt, textvariable = var.xlab_i[[i]], width = 20)

      var.label_i[[i]] <- tclVar(ifelse(is.na(varname), '', get(paste0(varname, '.label'))))
      entry.var.label[[i]] <- tkentry(opt, textvariable = var.label_i[[i]], width = 20)

    }


    tkgrid(tklabel(opt, text = 'Optional', anchor = 'e'),
           padx = 5, pady = 5, row = 0, columnspan = 4, sticky = 'w')

    tkgrid(tklabel(opt, text = 'Optional variable: ', anchor = 'w'),
           tklabel(opt, text = 'Axis label: ', anchor = 'w'),
           tklabel(opt, text = 'Plot label: ', anchor = 'w'),
           sticky = 'w', padx = 5, pady = 5, row = 1)


    for (j in 1:num_vars) {

      tkgrid(box.var[[j]], entry.var.xlab[[j]], entry.var.label[[j]],
             sticky = 'w', padx = 5, pady = 5, row = j + 1)

    }


    submit <- tkbutton(final, text = 'Submit', command = function() updatemm())

    tkgrid(submit, sticky = 'nse', padx = 5, pady = 5)


    tkgrid(labs, sticky = 'w')
    tkgrid(gr, sticky = 'w')
    tkgrid(sz, sticky = 'w')
    tkgrid(opt, sticky = 'w')
    tkgrid(final, sticky = 'e')
    tkgrid(overall)



    upsize <- function() {

      newsize <- as.numeric(tclvalue(currSize)) + 1
      tclvalue(currSize) <- as.character(newsize)


      lapply(p_label, function(pp) l_configure(pp, size = newsize))
      lapply(1:length(p_label_text), function(ii) l_configure(c(p_label[ii], p_label_text[ii]), size = newsize))

      lapply(p_scatterplot, function(ll) {

        lapply(ll, function(pp) l_configure(pp, size = newsize))

      })

    }


    downsize <- function() {

      s <- as.numeric(tclvalue(currSize))

      if (s == 1) {
        newsize <- 1
      } else {
        newsize <- s - 1
      }

      tclvalue(currSize) <- as.character(newsize)


      lapply(p_label, function(pp) l_configure(pp, size = newsize))
      lapply(1:length(p_label_text), function(ii) l_configure(c(p_label[ii], p_label_text[ii]), size = newsize))

      lapply(p_scatterplot, function(ll) {

        lapply(ll, function(pp) l_configure(pp, size = newsize))

      })

    }



    updatemm <- function() {

      # Disable any clicks until the code finishes running
      # (since optimization takes a long time to run)
      tcl(submit, 'configure', state = 'disabled')
      tcl('tk', 'busy', tt_inspector)


      if (identical(tclvalue(lab.label_i), '')) {
        lab.label_new <- 'Labels'
      } else {
        lab.label_new <- tclvalue(lab.label_i)
      }


      if (identical(tclvalue(map.label_i), '')) {
        map.label_new <- 'Maps'
      } else {
        map.label_new <- tclvalue(map.label_i)
      }


      grouping.var_new <- tclvalue(grouping.var_i)
      grouping.var.xlab_new <- tclvalue(grouping.var.xlab_i)
      grouping.var.label_new <- tclvalue(grouping.var.label_i)



      opt.vars <- Map(function(ii) {

        if (identical(tclvalue(var_i[[ii]]), 'N/A')) {
          return(NULL)
        } else {
          name <- tclvalue(var_i[[ii]])
        }

        xlab <- tclvalue(var.xlab_i[[ii]])

        label <- tclvalue(var.label_i[[ii]])


        list(name = name, xlab = xlab, label = label)

      }, 1:num_vars) %>% Filter(Negate(is.null), .)


      if (length(opt.vars) > 0) names(opt.vars) <- paste0('var', 1:length(opt.vars))


      if (identical(tclvalue(grouping_i), '')) {
        grouping_new <- NULL
      } else {
        grouping_new <- tclvalue(grouping_i) %>%
          strsplit(., ',') %>% unlist() %>%
          trimws() %>% as.numeric()
      }


      if (identical(tclvalue(n_groups_i), '')) {
        n_groups_new <- NULL
      } else {
        n_groups_new <- as.numeric(tclvalue(n_groups_i))
      }


      size_new <- as.numeric(tclvalue(currSize))


      variables <- c(list(id.var = id.var,
                          grouping.var = list(name = grouping.var_new,
                                              xlab = grouping.var.xlab_new,
                                              label = grouping.var.label_new)),
                     opt.vars)


      spdf@data <- spdf@data[, !(names(spdf@data) %in% c('linkingKey', 'group', names(more_states)))]


      tryCatch({

        l_micromaps(top = w$top, mm_inspector = FALSE,
                    spdf = spdf, grouping = grouping_new, n_groups = n_groups_new,
                    variables = variables, num_optvars = num_optvars,
                    map.label = map.label_new, lab.label = lab.label_new, title = title,
                    color = color_orig, size = size_new, spacing = spacing,
                    linkingKey = linkingKey, linkingGroup = linkingGroup, sync = sync, ...)

      }, error = function(err) {

        print(paste0('Linked micromaps update ran into the following error: ', err))

      })

      tcl('tk', 'busy', 'forget', tt_inspector)
      tcl(submit, 'configure', state = 'normal')

    }

    # Closes inspector window if the CCmaps display window is closed
    tkbind(w$top, '<Destroy>', function() tkdestroy(tt_inspector))

    # Do not allow inspector window to close otherwise
    tcl("wm", "protocol", tt_inspector, "WM_DELETE_WINDOW",
        quote(cat('To close inspector, close the main display window\n')))

    tt_inspector

  }

  if (mm_inspector) mmInspector(ret)


  return(invisible(ret))

}

