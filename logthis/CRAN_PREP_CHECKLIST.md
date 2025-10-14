# CRAN Submission Checklist for logthis

## ✅ Completed

- [x] Created NEWS.md with release notes
- [x] Created cran-comments.md for submission

## ⚠️ To Do Before Submission

### 1. Run R CMD check --as-cran

```r
# In R console:
devtools::check(cran = TRUE)

# Or via command line:
cd /home/siqi/projects/logthis/logthis
R CMD build .
R CMD check --as-cran logthis_0.1.0.tar.gz
```

**Must have:** 0 errors, 0 warnings, 0 notes

### 2. Replace \dontrun{} with \donttest{}

Found 10 files with `\dontrun{}`:
- R/contracts.R
- R/logger.R
- R/receiver-core.R
- R/receiver-handlers.R
- R/receiver-network.R
- R/tidylog-integration.R
- R/validation-helpers.R
- R/flush.R
- R/receiver-async.R
- R/receiver-formatters.R

**Action needed:**
```bash
# Search and review each usage:
grep -n "\\\\dontrun" /home/siqi/projects/logthis/logthis/R/*.R

# Decide for each:
# - Keep \dontrun{} if: interactive, requires credentials, destructive
# - Change to \donttest{} if: just slow or requires optional packages
```

**CRAN preference:** Use `\donttest{}` unless absolutely necessary

### 3. Update Version Number

In `DESCRIPTION`, change:
```
Version: 0.1.0.9000
```
to:
```
Version: 0.1.0
```

**When to do this:** Right before CRAN submission (not before soft launch)

### 4. Test on Multiple Platforms

Use `rhub::check_for_cran()`:
```r
rhub::check_for_cran()
# Or specific platforms:
rhub::check_on_windows()
rhub::check_on_macos()
rhub::check_on_linux()
```

**Required:** Must pass on Windows, macOS, and Linux

### 5. Check Example Timing

All examples must run in < 5 seconds:
```r
# Test example timing:
tools::testInstalledPackage("logthis", types = "examples")
```

**Fix if needed:** Wrap slow examples in `\donttest{}`

### 6. Verify Dependencies

Review DESCRIPTION:
- All Imports are actually imported
- All Suggests are actually used conditionally
- No unnecessary dependencies

```r
# Check for unused imports:
devtools::check(run_dont_test = TRUE)
```

### 7. Spell Check

```r
devtools::spell_check()
```

Fix any typos in documentation

### 8. Check URLs

All URLs in documentation must be valid:
```r
urlchecker::url_check()
```

### 9. Final Review

- [ ] README.md is up to date
- [ ] All vignettes build successfully
- [ ] pkgdown site builds cleanly
- [ ] LICENSE file exists and is correct
- [ ] DESCRIPTION has valid email
- [ ] No `.Rcheck` directories committed to git

## 📋 Before Submitting

1. **Wait 2-4 weeks after making repo public** to gather feedback
2. **Fix any issues** reported by users
3. **Update NEWS.md** with any changes
4. **Commit all changes** and push to GitHub
5. **Create GitHub release** with tag v0.1.0

## 🚀 Submission

```r
# Submit to CRAN:
devtools::release()

# Or manually:
# 1. Build: R CMD build logthis
# 2. Upload tarball to: https://cran.r-project.org/submit.html
# 3. Wait for automated checks
# 4. Respond to reviewer comments within 2 weeks
```

## ⏰ Expected Timeline

- **Soft launch:** Now - Week 2
- **User feedback:** Week 2 - Month 2
- **Bug fixes:** Month 2 - Month 3
- **CRAN submission:** Month 3
- **CRAN review:** 2-10 days after submission
- **CRAN publication:** After approval

## 📚 Resources

- CRAN Repository Policy: https://cran.r-project.org/web/packages/policies.html
- Writing R Extensions: https://cran.r-project.org/doc/manuals/R-exts.html
- R Packages book (2e): https://r-pkgs.org/
- rOpenSci Packaging Guide: https://devguide.ropensci.org/building.html
