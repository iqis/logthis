library(testthat)
library(purrr)

test_that("logger() & dummy_logger() produces right type.", {
    log_this <- logger()
    expect_s3_class(log_this,
                    "function")
    expect_s3_class(log_this,
                    "logger")

    log_this <- dummy_logger()
    expect_s3_class(log_this,
                    "function")
    expect_s3_class(log_this,
                    "logger")

})

test_that("logger()'s config attribute exists and has correct elements", {
    log_this <- logger()
    config <- attr(log_this, "config")

    expect_true(is.list(config))
    expect_setequal(names(config),
                    c("limits", "receivers", "receiver_calls"))
})

test_that("logger print method shows configuration", {
    log_this <- logger() %>%
        with_receivers(to_console(lower = WARNING)) %>%
        with_limits(lower = NOTE, upper = ERROR)
    
    # Capture print output
    output <- capture.output(print(log_this))
    
    # Should show it's a logger
    expect_true(any(grepl("<logger>", output)))
    
    # Should show level limits
    expect_true(any(grepl("Level limits:", output)))
    
    # Should show receiver information
    expect_true(any(grepl("Receivers:", output)))
    expect_true(any(grepl("to_console", output)))
})


TEST <- log_event_level("TEST", 50)
test_event <- TEST("Testing things.")

test_that("logger()() can map receivers to event and return event for chaining", {
    # Test that logger returns the original event
    result <- {
        log_this <- logger() %>%
            with_receivers(to_identity(),
                           to_void())
        log_this(test_event)
    }
    
    expect_equal(result, test_event)


    result2 <- {
        log_this <- logger() %>%
            with_receivers(to_identity(),
                           to_identity())
        log_this(test_event)
    }
    
    expect_equal(result2, test_event)
})


test_that("with_receivers() can guard logger and receiver types", {

    expect_error({
        fake_lgr <- function() NULL
        fake_lgr %>%
            with_receivers()
    })

    expect_warning({
        real_lgr <- logger()
        real_lgr %>%
            with_receivers() # empty `...`
    })

    expect_error({
        real_lgr <- logger()
        fake_rcvrs <- list(list(function(){"a"},
                                function(){"b"},
                                function(){"c"}),
                           function(){"d"})
        real_lgr %>%
            with_receivers(fake_rcvrs)
    })

})


test_that("with_receivers() returns type `logger`", {
    expect_s3_class({
        logger() %>% with_receivers(to_identity())
    }, "logger")
})

test_that("with_receivers() can add receivers to logger's config", {
    expect_equal({
        test_logger <- logger() %>%
            with_receivers(list(to_identity(),
                                to_void()),
                           to_identity())
        test_config <- attr(test_logger,
                            "config")
        test_config$receivers
    }, list(to_identity(),
            to_void(),
            to_identity())
    )
})

test_that("with_receivers() appends logger's receivers when `append` = TRUE (default)", {
    expect_equal({
        test_logger <- logger()  %>%
            with_receivers(to_identity()) %>%
            with_receivers(to_void())
        test_config <- attr(test_logger,
                            "config")
        test_config$receivers
    },
    list(to_identity(),
         to_void()))

})


test_that("with_receivers() overwrites logger's receivers when `append` = FALSE", {

    expect_equal({
        test_logger <- logger()  %>%
            with_receivers(to_identity()) %>%
            with_receivers(to_void(),
                           append = FALSE)
        test_config <- attr(test_logger,
                            "config")
        test_config$receivers
    },
    list(to_void()))
})


test_that("with_limits() can process different limit types", {
    # Test that with_limits can process numeric values and log event levels
    logger1 <- logger() %>%
        with_limits(1, 2)
    
    expect_s3_class(logger1, "logger")
    expect_equal(attr(logger1, "config")$limits$lower, 1)
    expect_equal(attr(logger1, "config")$limits$upper, 2)
    
    # Test with log event levels
    logger2 <- logger() %>%
        with_limits(WARNING(), ERROR())
    
    expect_s3_class(logger2, "logger")
    expect_equal(attr(logger2, "config")$limits$lower, 80)
    expect_equal(attr(logger2, "config")$limits$upper, 100)

})


test_that("with_limits() can guard logger, lower and upper types & values",{

    logger() %>%
        with_limits(0, 120)

    logger() %>%
        with_limits(LOWEST,
                    HIGHEST)


    expect_error({
        fake_lgr <- function() NULL
        fake_lgr %>%
            with_limits()
    })

    expect_s3_class({
        logger() %>%
            with_limits()
    }, "logger")

    expect_error({
        logger() %>%
            with_limits("foo",
                        list())

    })

    # must be within [0, 119] (lower)
    # must be within [1, 120] (upper)
    expect_error({
        logger() %>%
            with_limits(-1,
                        0)
    })

    expect_error({
        logger() %>%
            with_limits(120,
                        121)
    })

    expect_error({
        logger() %>%
            with_limits(1,
                        LOWEST)
    })
})

test_that("logger chaining works correctly", {
    # Create multiple loggers
    log_console <- logger() %>% with_receivers(to_identity())
    log_file <- logger() %>% with_receivers(to_void())
    
    # Chain them together
    result <- test_event %>%
        log_console() %>%
        log_file()
    
    # Should return the original event
    expect_equal(result, test_event)
})

test_that("scope-based logger enhancement works", {
    # Base logger
    base_logger <- logger() %>% with_receivers(to_identity())
    
    # Enhanced logger with additional receivers
    enhanced_logger <- base_logger %>% with_receivers(to_void())
    
    # Base logger should have 1 receiver
    expect_length(attr(base_logger, "config")$receivers, 1)
    
    # Enhanced logger should have 2 receivers
    expect_length(attr(enhanced_logger, "config")$receivers, 2)
    
    # Test the enhanced logger
    result <- enhanced_logger(test_event)
    expect_equal(result, test_event)
    expect_equal(attr(result, "receiver_results"), list(test_event, NULL))
})

test_that("two-level filtering works correctly", {
    # Create a logger with both logger-level and receiver-level filtering
    # Logger allows NOTE+ (40+), console receiver further filters to WARNING+ (80+)
    filtered_logger <- logger() %>%
        with_receivers(to_console(lower = WARNING)) %>%
        with_limits(lower = NOTE, upper = HIGHEST)
    
    # Test event below logger limit should be filtered out entirely
    low_event <- CHATTER("Below logger limit")  # level 20, below NOTE (40)
    result1 <- filtered_logger(low_event)
    expect_equal(result1, low_event)
    
    # Test event that passes logger but not receiver filter  
    mid_event <- NOTE("Passes logger, blocked by receiver")  # level 40, below WARNING (80)
    result2 <- filtered_logger(mid_event)
    expect_equal(result2, mid_event)
    
    # Test event that passes both filters
    high_event <- ERROR("Passes both filters")  # level 100, above both limits
    result3 <- filtered_logger(high_event)
    expect_equal(result3, high_event)
})

test_that("with_limits() returns type `logger`", {
    expect_s3_class({
        logger() %>% with_limits()
    }, "logger")
})
