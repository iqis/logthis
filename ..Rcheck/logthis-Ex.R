pkgname <- "logthis"
source(file.path(R.home("share"), "R", "examples-header.R"))
options(warn = 1)
library('logthis')

base::assign(".oldSearch", base::search(), pos = 'CheckExEnv')
base::assign(".old_wd", base::getwd(), pos = 'CheckExEnv')
cleanEx()
nameEx("logger")
### * logger

flush(stderr()); flush(stdout())

### Name: logger
### Title: Create a logger
### Aliases: logger dummy_logger

### ** Examples


log_this <- logger()




cleanEx()
nameEx("with_limits")
### * with_limits

flush(stderr()); flush(stdout())

### Name: with_limits
### Title: Set limits to a logger
### Aliases: with_limits

### ** Examples

log_this <- logger() %>%
    with_limits(lower = 20,
                upper = logthis::WARNING)



cleanEx()
nameEx("with_receivers")
### * with_receivers

flush(stderr()); flush(stdout())

### Name: with_receivers
### Title: Add receivers to a logger
### Aliases: with_receivers

### ** Examples


log_this <- logger() 
    with_receivers(to_identity(),
                   to_console())




### * <FOOTER>
###
cleanEx()
options(digits = 7L)
base::cat("Time elapsed: ", proc.time() - base::get("ptime", pos = 'CheckExEnv'),"\n")
grDevices::dev.off()
###
### Local variables: ***
### mode: outline-minor ***
### outline-regexp: "\\(> \\)?### [*]+" ***
### End: ***
quit('no')
