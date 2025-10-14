# logshiny

> **Shiny Integration for logthis**

<!-- badges: start -->
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

`logshiny` is a companion package to [`logthis`](../logthis/) that provides complete Shiny integration with 7 receivers and a unique inline alert panel system.

## Features

### 🎯 Inline Alert Panels (NEW!)

**Django/Rails-style message panels for Shiny** - display log events as Bootstrap alert panels with clean state management:

```r
library(shiny)
library(logthis)
library(logshiny)

ui <- fluidPage(
  alert_panel(
    "app_alerts",
    max_alerts = 5,
    dismissible = TRUE,
    auto_dismiss_ms = 5000,
    position = "top"
  ),
  textInput("name", "Name"),
  actionButton("submit", "Submit")
)

server <- function(input, output, session) {
  log_this <- logger() %>%
    with_receivers(to_alert_panel("app_alerts"))

  observeEvent(input$submit, {
    if (input$name == "") {
      log_this(WARNING("Name cannot be empty"))
    } else {
      log_this(NOTE(paste("Submitted:", input$name)))
    }
  })
}
```

**Key Features:**
- **Config-driven UI** - Set max alerts, position, auto-dismiss timing in `alert_panel()`
- **Full dismissal sync** - JS ↔ R callbacks ensure clean state (no ghost alerts)
- **Bootstrap styling** - Semantic colors (ERROR=red, WARNING=yellow, NOTE=blue)
- **Auto-stacking** - New alerts appear top or bottom with FIFO overflow
- **Zero custom JS** - All wiring handled automatically

### 🚨 Modal Alerts

- **`to_shinyalert()`** - Classic modal alerts (shinyalert package)
- **`to_sweetalert()`** - Modern SweetAlert2 modals (shinyWidgets package)

### 🔔 Toast Notifications

- **`to_notif()`** - Base Shiny notifications (`showNotification()`)
- **`to_show_toast()`** - shinyWidgets toast notifications
- **`to_toastr()`** - toastr.js toast notifications (shinytoastr package)

### 🛠️ Developer Tools

- **`to_js_console()`** ⭐ - Send R logs to browser DevTools console for debugging

## Installation

```r
# install.packages("devtools")
devtools::install_github("iqis/logthis", subdir = "logshiny")
```

**Note:** `logshiny` requires the `logthis` package:

```r
devtools::install_github("iqis/logthis", subdir = "logthis")
```

## Quick Start

### Inline Alert Panels

The recommended approach for user-facing messages:

```r
library(shiny)
library(logthis)
library(logshiny)

ui <- fluidPage(
  titlePanel("Form Validation Demo"),

  # Alert panel for user feedback
  alert_panel(
    "alerts",
    max_alerts = 3,
    dismissible = TRUE,
    auto_dismiss_ms = 5000
  ),

  textInput("email", "Email"),
  numericInput("age", "Age", 0),
  actionButton("submit", "Submit")
)

server <- function(input, output, session) {
  log_this <- logger() %>%
    with_receivers(
      to_alert_panel("alerts"),  # User-facing alerts
      to_console()                # Backend logging
    )

  observeEvent(input$submit, {
    # Validation with automatic UI feedback
    if (!grepl("@", input$email)) {
      log_this(ERROR("Invalid email address"))
    } else if (input$age < 18) {
      log_this(WARNING("Must be 18 or older"))
    } else if (input$age > 120) {
      log_this(WARNING("Age seems unrealistic"))
    } else {
      log_this(NOTE("Form submitted successfully!"))
      # ... process form
    }
  })
}

shinyApp(ui, server)
```

### Modal and Toast Notifications

For critical errors or background notifications:

```r
library(shiny)
library(logthis)
library(logshiny)

server <- function(input, output, session) {
  log_this <- logger() %>%
    with_receivers(
      to_shinyalert(lower = ERROR),              # Modals for errors
      to_show_toast(lower = WARNING, upper = WARNING),  # Toasts for warnings
      to_notif(lower = NOTE, upper = MESSAGE)    # Notifications for info
    )

  # Different log levels → different UI treatments
  log_this(NOTE("Process started"))          # → notification
  log_this(WARNING("Database slow"))         # → toast
  log_this(ERROR("Connection failed"))       # → modal alert
}
```

### Developer Debugging

Send R logs to browser DevTools console:

```r
library(shiny)
library(logthis)
library(logshiny)

ui <- fluidPage(
  shinyjs::useShinyjs(),  # Required for to_js_console()
  # ... your UI
)

server <- function(input, output, session) {
  log_this <- logger() %>%
    with_receivers(
      to_console(),      # R console
      to_js_console()    # Browser console (F12 DevTools)
    )

  # Logs appear in BOTH R console AND browser console
  log_this(DEBUG("Reactive value changed"))
  log_this(WARNING("Performance degrading"))
}
```

## API Reference

### UI Components

#### `alert_panel(output_id, ...)`

Creates a UI container for displaying log events as Bootstrap alert panels.

**Parameters:**
- `output_id` - Character; ID matching the `to_alert_panel()` receiver
- `max_alerts` - Integer; max alerts to display (FIFO overflow). Default: 10
- `dismissible` - Logical; show close button. Default: TRUE
- `auto_dismiss_ms` - Integer or NULL; auto-dismiss timeout. Default: NULL
- `position` - Character; "top" or "bottom" for newest alerts. Default: "top"
- `max_height` - Character; CSS max-height (e.g., "300px"). Default: NULL
- `show_clear_all` - Logical; show "Clear All" button. Default: FALSE
- `container_class` - Character; additional CSS classes. Default: NULL

**Example:**
```r
alert_panel(
  "alerts",
  max_alerts = 5,
  dismissible = TRUE,
  auto_dismiss_ms = 5000,
  position = "top",
  max_height = "400px",
  show_clear_all = TRUE
)
```

### Receivers

#### `to_alert_panel(output_id, lower, upper)`

Receiver for inline alert panels.

**Parameters:**
- `output_id` - Character; must match `alert_panel()` ID
- `lower` - Log event level; minimum to display. Default: LOWEST()
- `upper` - Log event level; maximum to display. Default: HIGHEST()

**Color Mapping:**
- ERROR/CRITICAL → red (`alert-danger`)
- WARNING → yellow (`alert-warning`)
- NOTE/MESSAGE → blue (`alert-info`)
- DEBUG/TRACE → gray (`alert-secondary`)

#### `to_shinyalert(lower, upper, ...)`

Modal alerts using shinyalert package.

#### `to_sweetalert(lower, upper, ...)`

SweetAlert2 modals using shinyWidgets package.

#### `to_notif(lower, upper, ...)`

Base Shiny notifications (`showNotification()`).

#### `to_show_toast(lower, upper, ...)`

Toast notifications using shinyWidgets.

#### `to_toastr(lower, upper, ...)`

Toastr.js notifications using shinytoastr package.

#### `to_js_console(lower, upper)`

Browser console logging (requires `shinyjs::useShinyjs()` in UI).

## Comparison with Other Frameworks

### Django (Python)

**Django flash messages:**
```python
# Django
from django.contrib import messages
messages.warning(request, "Database connection lost")
```

**logshiny equivalent:**
```r
# Shiny
log_this(WARNING("Database connection lost"))
```

### Ruby on Rails

**Rails flash:**
```ruby
# Rails
flash[:warning] = "Your session will expire soon"
```

**logshiny equivalent:**
```r
# Shiny
log_this(WARNING("Your session will expire soon"))
```

### Key Advantages

✅ **Unified logging** - Same logger for UI alerts AND backend logs
✅ **Level-based routing** - Automatic UI selection based on severity
✅ **Rich metadata** - Timestamps, tags, custom fields in every event
✅ **Shiny integration** - Works seamlessly with Shiny's reactive system
✅ **No custom JS** - Everything wired automatically via config

## Advanced Usage

### Differential Alert Styling

Different receivers for different severity levels:

```r
log_this <- logger() %>%
  with_receivers(
    to_alert_panel("critical", lower = ERROR),     # Panel for errors
    to_show_toast("warnings", lower = WARNING, upper = WARNING),  # Toasts for warnings
    to_console()  # All levels to console
  )
```

### Alert Panel + Audit Logging

Combine user-facing alerts with backend audit trail:

```r
log_this <- logger() %>%
  with_receivers(
    to_alert_panel("user_alerts", lower = WARNING),  # Users see warnings+
    to_json() %>% on_local("audit.jsonl"),           # All events logged
    to_console(lower = DEBUG)                        # Developers see all
  )
```

### Session-Specific Alert Panels

Each user session has isolated alert state:

```r
server <- function(input, output, session) {
  # Each session gets its own logger instance
  log_this <- logger() %>%
    with_receivers(to_alert_panel("user_alerts"))

  # User A's alerts don't appear for User B
  log_this(WARNING(paste("Welcome,", session$user)))
}
```

## Architecture

### Config Flow (UI → Server)

1. **UI renders** - `alert_panel()` creates container with embedded JS
2. **Session initializes** - JS fires, pushes config to `session$input`
3. **First log event** - `to_alert_panel()` reads config, initializes `renderUI()`
4. **Subsequent events** - Uses cached config from `session$userData`

### Dismissal Sync (JS ↔ R)

1. **User dismisses** - Bootstrap alert closes, JS callback fires
2. **JS → R** - `Shiny.setInputValue('{id}_dismissed', alert_id)`
3. **R observer** - Removes alert from reactiveVal queue
4. **Re-render** - UI updates with clean state (no ghost alerts)

### State Management

**Clean state principles:**
- Alert queue in `session$userData` (reactiveVal)
- Dismissals immediately update queue
- No memory leaks (dismissed = removed)
- FIFO overflow when max_alerts exceeded

## Dependencies

**Required:**
- logthis
- shiny
- htmltools
- jsonlite

**Optional (for specific receivers):**
- shinyalert (for `to_shinyalert()`)
- shinyWidgets (for `to_sweetalert()`, `to_show_toast()`)
- shinytoastr (for `to_toastr()`)
- shinyjs (for `to_js_console()`)

## Related Packages

- **[logthis](../logthis/)** - Core logging framework
- **[shinyalert](https://github.com/daattali/shinyalert)** - Modal alerts
- **[shinyWidgets](https://github.com/dreamRs/shinyWidgets)** - UI widgets
- **[shinytoastr](https://github.com/MangoTheCat/shinytoastr)** - Toast notifications
- **[shinyjs](https://github.com/daattali/shinyjs)** - JavaScript utilities

## License

MIT © logthis authors

## Contributing

Issues and pull requests welcome at https://github.com/iqis/logthis
