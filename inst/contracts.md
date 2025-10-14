# Function Contracts

**GENERATED FILE - Manual placeholder (run `Rscript dev/generate_contract_docs.R` to auto-generate)**

Source of truth: R/*.R files (executable contracts)
Generated: 2025-10-13 (Manual placeholder)

---

## Table of Contents

- [logger](#logger)
- [with_receivers](#with_receivers)
- [with_limits.logger](#with_limitsl ogger)
- [with_tags.logger](#with_tagslogger)
- [with_middleware.logger](#with_middlewarelogger)
- [receiver](#receiver)
- [log_event_level](#log_event_level)

---

## `logger()`

### Postconditions (Function's Guarantee)

- result is logger class
- result is function
- result has config
- config has limits
- config has receivers list
- limits are valid

**Source**: [`R/logger.R`](../R/logger.R)

---

## `with_receivers()`

### Preconditions (Caller's Responsibility)

- logger must be logger class
- append must be logical
- append must have length 1

### Invariants (Must Always Hold)

- receivers and labels match length
- receivers and names match length

### Postconditions (Function's Guarantee)

- result is logger
- result has config

**Source**: [`R/logger.R`](../R/logger.R)

---

## `with_limits.logger()`

### Preconditions (Caller's Responsibility)

- logger must be logger class
- lower must be in range [0, 99]
- upper must be in range [1, 100]
- lower must be <= upper

### Postconditions (Function's Guarantee)

- result is logger
- lower limit is valid
- upper limit is valid
- lower <= upper

**Source**: [`R/logger.R`](../R/logger.R)

---

## `with_tags.logger()`

### Preconditions (Caller's Responsibility)

- logger must be logger class
- append must be logical
- append must have length 1
- tag N must be character (for each tag)

### Postconditions (Function's Guarantee)

- result is logger
- tags are character

**Source**: [`R/logger.R`](../R/logger.R)

---

## `with_middleware.logger()`

### Preconditions (Caller's Responsibility)

- logger must be logger class
- middleware N must be function (for each middleware)

### Postconditions (Function's Guarantee)

- result is logger
- middleware is list
- all middleware are functions

**Source**: [`R/logger.R`](../R/logger.R)

---

## `receiver()`

### Preconditions (Caller's Responsibility)

- func must be function
- receiver must have exactly one argument
- receiver argument must be named event

### Postconditions (Function's Guarantee)

- result is log_receiver
- result is function

**Source**: [`R/receiver-core.R`](../R/receiver-core.R)

---

## `log_event_level()`

### Preconditions (Caller's Responsibility)

- level_class must be character
- level_class must not be missing
- level_class must not be null
- level_class must not be NA
- level_class must not be empty

### Postconditions (Function's Guarantee)

- result is log_event_level
- result is function
- result has level_number attribute
- result has level_class attribute
- level_number is in valid range

**Source**: [`R/log_event_levels.R`](../R/log_event_levels.R)

---

**Note**: This is a placeholder. Run `Rscript dev/generate_contract_docs.R` when dev environment is ready to auto-generate complete documentation from source code.
