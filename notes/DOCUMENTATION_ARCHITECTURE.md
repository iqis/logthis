# logthis Documentation Architecture

**Purpose**: Explain the single-source-of-truth system for maintaining logthis
**Audience**: Future maintainers (human and AI)
**Last Updated**: 2025-10-13

---

## Philosophy

**Code is truth. Documentation is a view into that truth.**

### Core Principles

1. **Single Source of Truth**: Every fact exists in exactly ONE place
2. **Executable Specifications**: Contracts are code, not comments
3. **Derived Documentation**: Generated docs extract from code
4. **Cross-Linked Navigation**: Multiple paths to same truth
5. **Minimal Redundancy**: Key concepts appear in multiple VIEWS, but same SOURCE

---

## Documentation Layers

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 1: SOURCE OF TRUTH (Code)                            │
│ ─────────────────────────────────────────────────────────  │
│ R/*.R files                                                 │
│ - Executable contracts (require_that, ensure_that)          │
│ - Type signatures in roxygen                                │
│ - Implementation defines behavior                           │
│                                                             │
│ tests/testthat/*.R files                                    │
│ - Executable specifications                                 │
│ - Define expected behavior                                  │
└─────────────────────────────────────────────────────────────┘
              │
              ├─────────────────┐
              │                 │
              ▼                 ▼
┌──────────────────────┐  ┌─────────────────────┐
│ Layer 2: EXTRACTED   │  │ Layer 2: CURATED    │
│ (Auto-Generated)     │  │ (Manual)            │
│ ──────────────────── │  │ ─────────────────── │
│ inst/contracts.md    │  │ notes/CLAUDE.md     │
│ - From: R/*.R        │  │ - Architecture      │
│ - Tool: generate_    │  │ - Patterns          │
│   contract_docs.R    │  │ - Gotchas           │
│ - Regenerate when    │  │ - Update when       │
│   code changes       │  │   arch changes      │
└──────────────────────┘  └─────────────────────┘
              │                 │
              └────────┬────────┘
                       │
                       ▼
         ┌───────────────────────────┐
         │ Layer 3: NAVIGATION INDEX │
         │ ───────────────────────── │
         │ inst/AI.md                │
         │ - Decision trees          │
         │ - Quick reference         │
         │ - Cross-links to layers 1 & 2 │
         │ - Update when structure   │
         │   changes                 │
         └───────────────────────────┘
```

---

## File Taxonomy

### Tier 1: SOURCE OF TRUTH (Never lies)

| File | What It Defines | When to Update |
|------|----------------|----------------|
| `R/*.R` | Function behavior, contracts, types | Every code change |
| `tests/testthat/*.R` | Expected behavior (executable spec) | Every behavior change |

**Rule**: If code and docs disagree, code wins.

---

### Tier 2a: EXTRACTED DOCS (Derived from code)

| File | Extracted From | How to Regenerate | Stale Indicator |
|------|---------------|-------------------|----------------|
| `inst/contracts.md` | `R/*.R` (contract calls) | `Rscript dev/generate_contract_docs.R` | Timestamp older than recent `R/*.R` changes |

**Rule**: NEVER edit manually. Always regenerate from code.

---

### Tier 2b: CURATED GUIDES (Human-maintained views)

| File | Purpose | When to Update | Content Type |
|------|---------|---------------|--------------|
| `notes/CLAUDE.md` | Complete architecture, patterns, gotchas | When architecture or patterns change | WHY and HOW (not WHAT - that's in code) |

**Rule**: Describes concepts, not specific function signatures. Links to code for details.

---

### Tier 3: NAVIGATION INDEX (Map to other docs)

| File | Purpose | When to Update | Content Type |
|------|---------|---------------|--------------|
| `inst/AI.md` | Decision trees, quick reference, cross-links | When structure or file organization changes | WHERE to look, not duplicating content |

**Rule**: Mostly links and decision trees. Minimal facts (only structural info).

---

## What Goes Where?

### Example: Function Signature

```r
# R/logger.R (SOURCE OF TRUTH)
#' @param void Logical flag
logger <- function(void = FALSE) {
  require_that("void is logical" = is.logical(void))  # Contract
  ...
}
```

**Extracted to**:
```markdown
# inst/contracts.md (AUTO-GENERATED)
## `logger()`
### Preconditions
- void is logical
```

**Referenced in**:
```markdown
# inst/AI.md (NAVIGATION)
**See**: `R/logger.R:43-127` for implementation
**Contracts**: `inst/contracts.md#logger`
```

**Described in**:
```markdown
# notes/CLAUDE.md (CURATED)
### Logger Creation
Loggers use closure pattern for immutability...
**Example**: See `R/logger.R` for full implementation
```

---

## Example: Adding a Feature

### Scenario: Add `with_timeout()` function to logger

#### Step 1: Write Code (Source of Truth)
```r
# R/logger.R
with_timeout <- function(logger, timeout_ms) {
  require_that(
    "logger is logger class" = inherits(logger, "logger"),
    "timeout_ms is positive number" = is.numeric(timeout_ms) && timeout_ms > 0
  )

  config <- attr(logger, "config")
  config$timeout_ms <- timeout_ms
  attr(logger, "config") <- config

  ensure_that(
    "result is logger" = inherits(logger, "logger"),
    "timeout is set" = !is.null(attr(logger, "config")$timeout_ms)
  )

  logger
}
```

#### Step 2: Write Tests (Executable Spec)
```r
# tests/testthat/test-logger.R
test_that("with_timeout sets timeout on logger", {
  log <- logger() %>% with_timeout(1000)
  expect_equal(attr(log, "config")$timeout_ms, 1000)
})
```

#### Step 3: Regenerate Extracted Docs
```bash
Rscript dev/generate_contract_docs.R
```

This AUTO-GENERATES in `inst/contracts.md`:
```markdown
## `with_timeout()`
### Preconditions
- logger is logger class
- timeout_ms is positive number
### Postconditions
- result is logger
- timeout is set
```

#### Step 4: Update Curated Guide (if architecture changed)
```markdown
# notes/CLAUDE.md
### Logger Configuration Functions
... (add with_timeout to list)
```

#### Step 5: Update Navigation (if structure changed)
```markdown
# inst/AI.md
## Core Functionality
- `R/logger.R` - ..., with_timeout, ...
```

---

## Checking for Staleness

### Is inst/contracts.md stale?

```bash
# Check if any R files modified after contracts.md
find R/ -name "*.R" -newer inst/contracts.md

# If output: regenerate contracts
Rscript dev/generate_contract_docs.R
```

### Is notes/CLAUDE.md accurate?

Manual review needed. Check:
1. Architecture diagrams match code
2. Patterns still used in codebase
3. Gotchas still relevant

### Is inst/AI.md current?

Check:
1. Do decision trees point to correct files?
2. Are file locations accurate?
3. Do cross-links work?

---

## Redundancy vs. Duplication

### ✅ GOOD: Multiple REPRESENTATIONS of same concept

**Concept**: "Receivers must return invisible(NULL)"

- **Code** (`R/receiver-core.R`): Enforced in `receiver()` constructor
- **Contract** (`inst/contracts.md`): Listed as postcondition
- **Curated** (`notes/CLAUDE.md`): Explained WHY (enables chaining)
- **Navigation** (`inst/AI.md`): Listed in gotchas with link to code

**Reason**: Different audiences need different views. But all point to SAME source.

---

### ❌ BAD: DUPLICATION of facts

**Don't**:
```markdown
# inst/AI.md
logger() accepts void parameter of type logical, defaults to FALSE

# notes/CLAUDE.md
Function logger(void = FALSE) takes a logical parameter
```

**Do**:
```markdown
# inst/AI.md
**See**: `R/logger.R:logger()` - Creates logger instance

# notes/CLAUDE.md
Loggers are created with `logger()` function.
**Signature**: See `R/logger.R` for details
```

---

## Maintenance Checklist

### After modifying code

- [ ] Update contracts in code (require_that, ensure_that)
- [ ] Update/add tests
- [ ] Run: `Rscript dev/generate_contract_docs.R`
- [ ] Run: `devtools::document()` (for roxygen)
- [ ] Run: `devtools::test()` (verify specs)
- [ ] If architecture changed: Update `notes/CLAUDE.md`
- [ ] If file structure changed: Update `inst/AI.md`

### Monthly review

- [ ] Check for stale `inst/contracts.md` (regenerate if needed)
- [ ] Verify `notes/CLAUDE.md` architecture diagrams
- [ ] Verify `inst/AI.md` decision trees still valid
- [ ] Check all cross-links work

---

## Tools

### Current

| Tool | Purpose | Location |
|------|---------|----------|
| `generate_contract_docs.R` | Extract contracts from code | `dev/generate_contract_docs.R` |

### Future Enhancements

| Tool | Purpose | Status |
|------|---------|--------|
| `check_stale_docs.R` | Find docs older than code | TODO |
| `verify_cross_links.R` | Check all links resolve | TODO |
| `generate_dep_graph.R` | Extract function dependencies | TODO |

---

## For AI Assistants

### When reading logthis code:

1. **Start with**: `inst/AI.md` (navigation index)
2. **For specific function**: Check `inst/contracts.md` (auto-generated spec)
3. **For architecture**: Read `notes/CLAUDE.md` (curated guide)
4. **For ground truth**: Always read `R/*.R` files (source of truth)

### When modifying logthis code:

1. **Before**: Read contracts in `inst/contracts.md`
2. **During**: Add contracts to `R/*.R` file
3. **After**: Regenerate `inst/contracts.md`
4. **If needed**: Update `notes/CLAUDE.md` (architecture) or `inst/AI.md` (navigation)

### If you find discrepancy:

1. **Trust**: Code in `R/*.R`
2. **Verify**: Tests in `tests/testthat/`
3. **Fix**: Regenerate `inst/contracts.md`
4. **Update**: `notes/CLAUDE.md` or `inst/AI.md` if needed

---

## Questions?

- **"Where is the source of truth for X?"** → Code in `R/*.R` or tests in `tests/testthat/`
- **"Can I edit inst/contracts.md?"** → NO. Regenerate from code.
- **"When to update notes/CLAUDE.md?"** → When architecture/patterns change, not function signatures.
- **"What if code and docs disagree?"** → Code wins. Update docs.

---

**Remember**: Code is truth. Docs are maps to that truth. Good maps don't duplicate the territory - they help you navigate it.
