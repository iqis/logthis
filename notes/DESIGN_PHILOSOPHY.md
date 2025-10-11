# logthis Design Philosophy

**Date:** 2025-10-11
**Status:** Core principles established during helper function refactoring

---

## The Essential Spirit

> **Build a minimal, powerful foundation. Trust users to know their domain better than you do.**

The package provides composable primitives, not opinionated solutions. We teach patterns, not prescribe implementations.

---

## Core Tenets

### 1. Primitives Over Abstractions
**"If it's just a wrapper, it doesn't belong in the package."**

- Export only functions that do *real work*
- Remove syntactic sugar that obscures the primitive
- `with_tags()` is the primitive; everything else is composition

**Test:** Can users do this in 1-2 lines with primitives? Then don't export a helper.

---

### 2. No Assumptions, Ever
**"The package doesn't know your domain."**

- Never hardcode: paths, formats, destinations, configurations
- Don't assume JSON over CSV, local over cloud, development over production
- Users choose their tools; we provide the building blocks

**Test:** Does this function make decisions for the user? Remove it.

---

### 3. Scope-Based Pattern
**"One name, many configurations."**

- Always use `log_this` - configure it in scopes
- Leverage R's lexical scoping (like Shiny's `ns()`)
- Easy refactoring: move code without renaming loggers

**Test:** Am I creating `log_app`, `log_db`, `log_api`? Use `log_this` instead.

---

### 4. Separation of Concerns
**"Logging writes. Analysis reads. These are different jobs."**

- Package logs events to destinations
- Users analyze with their own tools (dplyr, SQL, etc.)
- Don't blur the boundary

**Test:** Is this about reading/querying logs? It's not our concern.

---

### 5. Patterns in Vignettes, Not Functions in Code
**"Teach, don't prescribe."**

- Document patterns users can customize
- Show GxP setup, pipeline logging, environment configs as *examples*
- Users copy, adapt, own the code

**Test:** Would different users need this configured differently? Make it a pattern, not a function.

---

### 6. Functional Composition
**"Build big things from small pieces."**

- Pipe-friendly design (`%>%`)
- Closure-based configuration
- Immutable operations (return new, don't mutate)

**Test:** Can this be composed? Does it return a new object?

---

### 7. Trust the User
**"Users are domain experts in their own field."**

- Pharmaceutical users know GxP better than we do
- Pipeline users know their data workflows
- API users know their monitoring needs
- Provide tools, not solutions

**Test:** Am I making domain-specific decisions for users? Stop.

---

## What This Means In Practice

### ✅ Do This:
- Export powerful primitives (`with_tags`, `with_receivers`, `with_limits`)
- Show patterns in vignettes (environment setup, GxP logging, pipeline audit)
- Let users build helpers in *their* code for *their* domain
- Document clearly what fields go where (tags vs custom fields)
- Make behavior predictable and transparent

### ❌ Don't Do This:
- Export `component_logger()` - it's just `with_tags(component = ...)`
- Hardcode `to_json() %>% on_local("audit.jsonl")` - users pick format and destination
- Create `filter_by_tags()` - log analysis is user's concern, not ours
- Assume we know what "production" or "staging" means for users

---

## The Refactoring Test

Before adding a helper function, ask:

1. **Does it wrap primitives?** → Document the pattern, don't export
2. **Does it make assumptions?** → Let users configure it
3. **Is it domain-specific?** → Show an example, don't prescribe
4. **Can users do it themselves easily?** → They should

**If all answers are "yes", it's not a core function.**

---

## The Result

A package that:
- Has a **small, focused surface area**
- Is **endlessly flexible** for different domains
- **Teaches users** to build what they need
- Makes **no assumptions** about their use case
- **Trusts domain experts** to know their needs

---

## Guiding Questions for Future Work

**When adding features:**
- "Am I adding a primitive or a convenience wrapper?"
- "Does this make assumptions about how users will use it?"
- "Could this be a vignette pattern instead of exported code?"

**When reviewing code:**
- "Is this the smallest, most powerful version of this idea?"
- "Does this trust users to know their domain?"
- "Are we teaching or prescribing?"

---

## Summary

**The spirit:** Build a sharp, focused tool. Show people how to use it. Trust them to build what they need.

**The practice:** Minimal core API. Maximum flexibility. Patterns in docs, not functions in code.

**The test:** If you're making decisions for the user's domain, you're doing it wrong.

---

*"The best API is the one that gets out of your way."*
