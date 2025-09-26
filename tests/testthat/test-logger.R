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
                    c("limits", "receivers"))
})


TEST <- log_event_level("TEST", 50)
test_event <- TEST("Testing things.")

test_that("logger()() can map receivers to event", {
    expect_equal({
        log_this <- logger() %>%
            with_receivers(to_zero(),
                           to_one())
        log_this(test_event)
    },
    list(0, 1))


    expect_equal({
        log_this <- logger() %>%
            with_receivers(to_identity(),
                           to_one())
        log_this(test_event)
    },
    list(test_event,
         1))
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


test_that("normalize_limit() can normalize limits", {

    expect_equal(normalize_limit(1),
                 1)

    expect_equal(normalize_limit(1.4),
                 1)

    expect_equal(normalize_limit(1.5),
                 2)

    expect_equal(normalize_limit(WARNING),
                 80)

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

    expect_message({
        logger() %>%
            with_limits()
    })

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

test_that("with_limits() returns type `logger`", {
    expect_s3_class({
        logger() %>% with_limits()
    }, "logger")
})
