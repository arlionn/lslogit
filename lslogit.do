/*****************************************************************************
 *
 * lslogit -- ESTIMATING MIXED LOGIT LABOR SUPPLY MODELS WITH STATA
 * 
 * (c) 2012 - Max L�ffler
 *
 *****************************************************************************/

cap program drop lslogit
/**
 * Conditional Logit but integrating out wage prediction errors (Wrapper programm)
 * 
 * @param `group'  Group identifier variable
 * @param `taxreg' Stored estimates of the tax regression
 */
program define lslogit
    if (replay()) {
        if (`"`e(cmd)'"' != "lslogit")   error 301
        lslogit_Replay `0'
    }
    else lslogit_Estimate `0'
end

cap program drop lslogit_Replay
/**
 * Conditional Logit but integrating out wage prediction errors (Wrapper programm)
 * 
 * @param `group'  Group identifier variable
 * @param `taxreg' Stored estimates of the tax regression
 */
program define lslogit_Replay
    syntax [, Level(integer `c(level)') Quiet]
    
    // Set up auxiliary stuff
    local diparm
    if ("`quiet'" == "") {
        foreach aux in sigma_w1 sigma_w2 dudes {
            if (e(`aux') != .) {
                local val = e(`aux')
                local diparm `diparm' diparm(__lab__, value(`val') label("[`aux']"))
            }
        }
    }
    
    // Display output
    ml display, level(`level') `diparm'
                               /*diparm(ln_consum, f(`dudes') d(0) label("% dU/dc>=0"))*/
end

cap program drop lslogit_Estimate
/**
 * Conditional Logit but integrating out wage prediction errors (Wrapper programm)
 * 
 * @param `group' varname  Group identifier variable
 * @param `taxreg' name Stored estimates of the tax regression
 * @param `burn' integer Number of initial Halton draws to burn
 */
program define lslogit_Estimate, eclass
    syntax varname(numeric) [if] [in] [fweight/], GRoup(varname numeric) Ufunc(name)                                    ///
                                                  Consumption(varname numeric) Leisure(varlist numeric min=1 max=2)     ///
                                                  [cx(varlist numeric)  lx1(varlist numeric)  lx2(varlist numeric)      ///
                                                   c2x(varlist numeric) l2x1(varlist numeric) l2x2(varlist numeric)     ///
                                                   INDeps(varlist) TOTALTime(integer 80) DAYs(varname numeric)          ///
                                                   HWage(varlist numeric min=1 max=2)                                   ///
                                                   TAXReg(name) tria1(varlist numeric) tria2(varlist numeric)           ///
                                                   WAGEPred(varlist numeric min=1 max=2) HECKSIGma(numlist min=1 max=2) ///
                                                   RANDvars(string) corr DRaws(integer 50) burn(integer 15)             ///
                                                   HECKMan(varlist) SELect(varlist)                                     ///
                                                   noround Quiet Verbose                                                ///
                                                   difficult trace search(name) iterate(integer 100) method(name)       ///
                                                   gradient hessian debug Level(integer `c(level)')]
    
    /* INITIALIZE ESTIMATOR
     */
    
    // Mark the estimation sample
    marksample touse
    markout `touse' `varlist' `group' `consumption' `leisure' `cx' `lx1' `lx2' `c2x' `l2x1' `l2x2'  ///
                    `indeps'`wagepred' `days' `tria1' `tria2' `heckman' `select'
    
    // Verbose mode
    if ("`verbose'" == "") local qui qui
    
    // Validate Maximum Likelihood method
    if ("`method'" == "") local method d2
    if (!inlist("`method'", "d0", "d1", "d2")) {
        di in r "method must be either 'd0', 'd1' or 'd2'"
        exit 498
    }
    
    // Validate utility function
    if (!inlist("`ufunc'", "quad", "tran")) {
        di in r "utility function must be either 'quad' or 'tran'"
        exit 498
    }
    // If translog, set up pre-text and check for zeros
    if ("`ufunc'" == "tran") {
        local ln  "ln"
        local pre "`ln'_"
        qui count if log(`consumption') == . & `touse'
    }
    else {
        qui count if `consumption' < 0 & `touse'
    }
    // Check for negative values
    if (r(N) > 0) {
        di in r "consumption contains values smaller or equal to zero"
        exit 498
    }
    
    // Validate joint estimation settings
    if ("`select'" != "" & "`heckman'" == "") {
        di in r "option heckman() required when estimating jointly"
        exit 498
    }
    if ("`heckman'" != "" & "`hwage'" == "") {
        di in r "option hwage() required when estimating jointly"
        exit 498
    }
    if ("`heckman'" != "") {
        qui count if `hwage' == .
        if ("`select'" != "" & r(N) == 0) {
            di in r "wage variable never censored because of selection"
            exit 498
        }
        else if ("`select'" == "" & r(N) > 0) {
            di in r "wage variable censored, use option select()"
            exit 498
        }
    }
    
    // Get variable count
    local n_leisure  : word count `leisure'
    local n_cxias    : word count `cx'
    local n_lx1ias   : word count `lx1'
    local n_lx2ias   : word count `lx2'
    local n_c2xias   : word count `c2x'
    local n_l2x1ias  : word count `l2x1'
    local n_l2x2ias  : word count `l2x2'
    local n_indeps   : word count `indeps'
    local n_randvars : word count `randvars'
    local n_wagep    : word count `wagepred'
    local n_hwage    : word count `hwage'
    local n_hecksig  : word count `hecksigma'
    local n_taxrias1 : word count `tria1'
    local n_taxrias2 : word count `tria2'
    local n_heckvars : word count `heckman'
    local n_selvars  : word count `select'
    
    // Validate Wage Prediction Options
    if (`n_wagep' == 0) {
        local wagep = 0     // No wage prediction
    }
    else {
        // Wage prediction enabled
        if (`n_wagep' == `n_leisure' & `n_wagep' == `n_hwage' & `n_wagep' == `n_hecksig') {
            tempvar preds
            qui egen `preds' = rowtotal(`wagepred') if `touse'
            qui count if inlist(`preds', 1, 2) & `touse'
            local wagep = (r(N) > 0)
        }
        // Settings incorrect
        else {
            di in r "number of wage prediction variables does not match the number of leisure terms, hourly wage rates or mean squared errors"
            exit 498
        }
    }
    
    // No need for random variables
    if (`wagep' == 0 & "`randvars'" == "") local draws = 1
    
    // Tax regression or tax benefit calculator needed
    if (`wagep' == 1 | "`heckman'" != "") {
        if ("`taxreg'" != "" & "`taxben'" == "") {
            tempname taxreg_from
            // Load tax regression estimates
            qui est restore `taxreg'
            mat `taxreg_from' = e(b)
            local taxreg_betas : colnames `taxreg_from'
            local n_taxreg_betas : word count `taxreg_betas'
            local taxreg_vars
            local start = 1 + 2 * (`n_leisure' + `n_taxrias1' + `n_taxrias2')         // + `n_leisure' * 5
            forval x = `start'/`n_taxreg_betas' {
                local var : word `x' of `taxreg_betas'
                if ("`var'" != "_cons") local taxreg_vars `taxreg_vars' `var'
            }
        }
        // Run tax benefit calculator
        else if ("`taxreg'" == "" & "`taxben'" != "") {
            //
        }
        // Either taxben or taxreg have to be specified
        else {
            di in r "either option taxreg() or option taxben() required"
            exit 198
        }
    }
    
    // Build weight settings
    if ("`weight'" != "")   local wgt "[`weight'=`exp']"
    
    // Select random variables
    local rvars = `n_randvars' + `n_wagep'
    
    
    /* LOOK FOR INITIAL VALUES
     */
    
    if ("`search'" != "off") {
        // Verbose mode on?
        if ("`verbose'" != "") di as text "Looking for initial values..."
        
        // Set up consumption and leisure
        tempvar c l1 l2
        if ("`ufunc'" == "tran") {
            qui gen `c' = log(`consumption') if `touse'
            foreach var of local leisure {
                if (strpos("`leisure'", "`var'") == 1) local lei l1
                else                                   local lei l2
                qui gen ``lei'' = log(`var') if `touse'
            }
        }
        else {
            qui gen `c' = `consumption' if `touse'
            foreach var of local leisure {
                if (strpos("`leisure'", "`var'") == 1) local lei l1
                else                                   local lei l2
                qui gen ``lei'' = `var' if `touse'
            }
        }
        
        // Build up var list for search of initial values
        local initrhs
        if (`n_leisure' == 2) local leisurelist l1 l2
        else                  local leisurelist l1
        foreach ia in c `leisurelist' {
            local f = substr("`ia'", 1, 1)
            if (strlen("`ia'") == 2) local l = substr("`ia'", 2, 1)
            else local l
            foreach var in ``f'x`l'' 0 {
                if ("`var'" != "0") local initrhs `initrhs' c.``ia''#c.`var'
                else                local initrhs `initrhs' ``ia''
            }
            foreach var in ``f'2x`l'' 0 {
                if ("`var'" != "0") local initrhs `initrhs' c.``ia''#c.``ia''#c.`var'
                else                local initrhs `initrhs' c.``ia''#c.``ia''
            }
            if ("`ia'" == "c") {
                foreach lei of local leisurelist {
                    local initrhs `initrhs' c.`c'#c.``lei''
                }
            }
        }
        // Leisure cross term
        if (`n_leisure' == 2) local initrhs `initrhs' c.`l1'#c.`l2'
        // Add independent variables to var list
        local initrhs `initrhs' `indeps'
        
        // Estimate
        tempname init_from
        mat `init_from' = J(1, 2 + 2 * `n_leisure' + `n_cxias' + `n_lx1ias' + `n_lx2ias' + `n_indeps', 0)
        `qui' clogit `varlist' `initrhs' if `touse' `wgt', group(`group') iterate(25)
        if (e(converged) == 1) {
            // Save results
            mat `init_from' = e(b)
            local nobs      = e(N)
            local k         = e(k)
            local ll        = e(ll)
            // Update sample
            qui replace `touse' = e(sample)
        }
        
        // Wage equation
        if ("`heckman'" != "") {
            tempname init_wage init_w
            if (`n_hwage' == 0) mat `init_wage' = J(1, 1 + `n_heckvars' * `n_leisure', 0)
            else {
                foreach w of local hwage {
                    tempvar ln`w'
                    qui gen `ln`w'' = ln(`w') if `touse' & `varlist'
                    if ("`select'" != "") {
                        `qui' heckman `ln`w'' `heckman' if `touse' & `varlist' `wgt', select(`select')
                        mat `init_w' = e(b)
                        mat `init_w'[1,colsof(`init_w')-1] = e(rho)
                        mat `init_w'[1,colsof(`init_w')] = e(sigma)
                        //mat `init_w' = `init_w'[1,1..colsof(`init_w')-1]
                    }
                    else {
                        `qui' reg `ln`w'' `heckman' if `touse' & `varlist' `wgt'
                        mat `init_w' = e(b)
                    }
                    mat `init_wage' = (nullmat(`init_wage'), `init_w')
                }
            }
        }
        
        // Save init options
        local initopt init(`init_from', copy) obs(`nobs') lf0(`k' `ll')
    }
    else {
        qui count if `touse'
        local nobs = r(N)
    }
    
    
    /* PREPARING DATA
     */
    
    if ("`verbose'" != "") di as text "Preparing data..."
    
    // Drop missing data
    preserve
    qui keep if `touse'
    sort `group' //`leisure'
    
    // Setup data
    mata: ml_round  = ("`round'" != "noround")                                                      // To round, or not to round?
    mata: ml_ufunc  = st_local("ufunc")                                                             // Utility function
    mata: ml_Weight = ("`exp'" != "" ? st_data(., st_local("exp")) : J(`nobs', 1, 1))               // Weight
    mata: ml_Y      = st_data(., st_local("varlist"))                                               // Left hand side
    mata: ml_Hwage  = (`n_hwage' > 0 ? st_data(., tokens("`hwage'")) : J(`nobs', `n_leisure', 0))   // Hourly wage rates
    
    //
    // Right hand side
    //
    mata: ml_C   = st_data(., st_local("consumption"))                                          // Consumption
    mata: ml_CX  = (`n_cxias'  > 0 ? st_data(., tokens(st_local("cx")))  : J(`nobs', 0, 0))     // Interactions with consumption
    mata: ml_C2X = (`n_c2xias' > 0 ? st_data(., tokens(st_local("c2x"))) : J(`nobs', 0, 0))     // Interactions with consumption^2
    forval i = 1/2 {                                                                            // Leisure and interactions
        local var : word `i' of `leisure'
        mata: ml_L`i'   = ("`var'"      != "" ? st_data(., st_local("var"))            : J(`nobs', 0, 0))
        mata: ml_LX`i'  = (`n_lx`i'ias'  >  0 ? st_data(., tokens(st_local("lx`i'")))  : J(`nobs', 0, 0))
        mata: ml_L2X`i' = (`n_l2x`i'ias' >  0 ? st_data(., tokens(st_local("l2x`i'"))) : J(`nobs', 0, 0))
    }
    mata: ml_Xind = (`n_indeps' > 0 ? st_data(., tokens(st_local("indeps"))) : J(`nobs', 0, 0)) // Dummy variables
    if ("`ufunc'" == "tran") {                                                                  // Right hand side (translog)
        mata: ml_X = (log(ml_C)  :* (ml_CX,  J(`nobs', 1, 1), log(ml_C) :*ml_C2X,  log(ml_C),   log(ml_L1), log(ml_L2)),          ///
                      log(ml_L1) :* (ml_LX1, J(`nobs', 1, 1), log(ml_L1):*ml_L2X1, log(ml_L1)), ///
                      log(ml_L2) :* (ml_LX2, J(`nobs', 1, 1), log(ml_L2):*ml_L2X2, log(ml_L2)), log(ml_L1):*log(ml_L2), ml_Xind)
    }
    else if ("`ufunc'" == "quad") {                                                             // Right hand side (quad)
        mata: ml_X = (ml_C  :* (ml_CX,  J(`nobs', 1, 1), ml_C :*ml_C2X,  ml_C,   ml_L1, ml_L2),              ///
                      ml_L1 :* (ml_LX1, J(`nobs', 1, 1), ml_L1:*ml_L2X1, ml_L1),     ///
                      ml_L2 :* (ml_LX2, J(`nobs', 1, 1), ml_L2:*ml_L2X2, ml_L2), ml_L1:*ml_L2, ml_Xind)
    }
    else mata: ml_X = J(`nobs', 0, 0)
    
    //
    // Joint wage estimation
    //
    mata: ml_heckm      = ("`heckman'" != "")                                                                                       // Run joint estimation?
    mata: ml_HeckmVars  = (ml_heckm == 1 ? (st_data(., tokens("`heckman'")), J(`nobs', 1, 1)) : J(`nobs', 0, 0))                    // Wage variables
    mata: ml_SelectVars = (ml_heckm == 1 & "`select'" != "" ? (st_data(., tokens("`select'")), J(`nobs', 1, 1)) : J(`nobs', 0, 0))  // Wage variables
    mata: ml_Days       = ("`days'" != "" ?  st_data(., st_local("days")) : J(`nobs', 1, 365))                                      // Days of taxyear
    mata: ml_Hours      = `totaltime' :- (ml_L1, ml_L2)                                                                             // Hypothetical hours
    
    //
    // Wage Prediction Stuff
    //
    mata: ml_wagep = `wagep'                                                            // Run Wage Prediction
    if (`wagep' == 1) {
        mata: ml_Wpred = st_data(., ("`wagepred'"))                                     // Dummies enabling or disabling the wage prediction
        mata: ml_Sigma = J(1, `n_hecksig', 0)                                           // Estimated variance of Heckman correction
        forval i = 1/`n_hecksig' {
            local sig : word `i' of `hecksigma'
            mata: ml_Sigma[1,`i'] = `sig'
        }
    }
    
    //
    // Tax regression
    //
    if ("`taxreg'" != "") {
        mata: ml_TaxregB    = st_matrix("`taxreg_from'")                                            // Tax regression estimates
        mata: ml_TaxregIas1 = ("`tria1'" != "" ? st_data(., tokens("`tria1'")) : J(`nobs', 0, 0))   // Interaction variables on Mwage1 and Mwage1^2
        mata: ml_TaxregIas2 = ("`tria2'" != "" ? st_data(., tokens("`tria2'")) : J(`nobs', 0, 0))   // Interaction variables on Mwage2 and Mwage2^2
        mata: ml_TaxregVars = st_data(., tokens("`taxreg_vars'"))                                   // Variables that are independent of m_wage
    }
    
    //
    // Group level stuff
    //
    qui duplicates report `group'
    mata: ml_groups = st_numscalar("r(unique_value)")   // Number of groups
    tempvar choices
    by `group': gen `choices' = _N
    mata: ml_J = st_data(., st_local("choices"))        // Choices per group
    
    //
    // Random draws
    //
    mata: ml_draws = strtoreal(st_local("draws"))                                                                   // Number of draws
    mata: ml_burn  = strtoreal(st_local("burn"))                                                                    // Number of draws to burn
    mata: st_local("randvars", invtokens(strofreal(sort(strtoreal(tokens("`randvars'"))', 1))'))                    // Sort random coefficients
    mata: ml_Rvars = ("`randvars'" != "" ? strtoreal(tokens("`randvars'"))' : J(0, 0, 0))                           // Random coefficients
    mata: ml_corr  = ("`corr'" != "")                                                                               // Random coefficients correlated?
    mata: ml_R     = (`rvars' > 0 ? invnormal(halton(ml_groups*ml_draws, `rvars', 1+ml_burn)) : J(`nobs', 0, 0))    // Halton sequences
    
    // Restore data
    restore
    
    
    /* RUN ESTIMATION
     */
    
    if ("`verbose'" != "") di as text "Run estimation..."
    
    // Set up equations
    local eq_consum (C: `varlist' = `cx') (CC: `c2x')       // Consumption and consumption^2
    local eq_leisure
    foreach var of local leisure {
        local i = 1 + (strpos("`leisure'", "`var'") > 1)
        local eq_leisure `eq_leisure' (L`i': `lx`i'') (L`i'L`i': `l2x`i'')  // Leisure and leisure^2
        local eq_consum  `eq_consum' /CXL`i'                                // Consumption X leisure interaction
    }
    if (`n_leisure' == 2) local eq_leisure  `eq_leisure' /L1XL2         // Leisure term interaction
    if (`n_indeps'  >  0) local eq_indeps   (IND: `indeps', noconst)    // Independent variables / dummies
    // Random coefficients
    if (`n_randvars' > 0) {
        local eq_rands
        if ("`corr'" == "") {
            forval i = 1/`n_randvars' {
                local sd : word `i' of `randvars'
                local eq_rands `eq_rands' /sd_`sd'
            }
            if ("`initopt'" != "") mat `init_from' = (`init_from', J(1, `n_randvars', 0.0001))
        }
        else {
            forval i = 1/`n_randvars' {
                local a : word `i' of `randvars'
                forval k = `i'/`n_randvars' {
                    local b : word `k' of `randvars'
                    if (`a' == `b') local lab sd_`a'
                    else local lab s_`a'_`b'
                    local eq_rands `eq_rands' /`lab'
                }
            }
            if ("`initopt'" != "") mat `init_from' = (`init_from', J(1, `n_randvars' * (`n_randvars' + 1) / 2, 0.0001))
        }
    }
    // Joint wage estimation
    if ("`heckman'" != "") {
        local eq_heckm (lnW: `heckman')
        if ("`select'"  != "") local eq_heckm `eq_heckm' (S: `select') /athrho /lnsigma
        if ("`initopt'" != "") mat `init_from' = (`init_from', `init_wage')
    }
    
    // Estimate
    ml model `method'`debug' lslogit_d2() `eq_consum' `eq_leisure' `eq_indeps' `eq_rands' `eq_heckm' ///
            if `touse' `wgt', group(`group') `initopt' search(off) iterate(`iterate') nopreserve max `difficult' `trace' `gradient' `hessian'
    
    // Save results
    ereturn local  title    "Mixed Logit Labor Supply Model"
    ereturn local  cmd      "lslogit"
    ereturn local  predict  "izamodP"
    ereturn local  depvar    `varlist'
    ereturn local  group     `group'
    ereturn local  ufunc    "`ufunc'"
    ereturn scalar draws   = `draws'
    if ("`select'" != "") ereturn scalar k_aux = 2
    else {
        if ("`corr'" != "") {
            ereturn scalar corr  = 1
            ereturn scalar k_aux = `n_randvars' * (`n_randvars' + 1) / 2
        }
        else {
            ereturn scalar corr = 0
            ereturn scalar k_aux = `n_randvars'
        }
    }
    
    foreach aux in sigma_w1 sigma_w2 dudes {
        if (r(`aux') != .) ereturn scalar `aux' = r(`aux')
    }
    
    // Show results
    lslogit_Replay, level(`level') `quiet'
end

cap mata mata drop lslogit_d2()
mata:
/**
 * Standard Conditional Logit but integrating out wage prediction errors (Evaluator)
 * 
 * @param B_s Stata matrix of coefficients
 */
void lslogit_d2(transmorphic scalar ML, real scalar todo, real rowvector B,
                real scalar lnf, real rowvector G, real matrix H) {
    
    external ml_ufunc           // Functional form
    external ml_groups          // Number of groups
    external ml_Y               // Left hand side variable
    external ml_J               // Number of choices per group
    external ml_X               // Right hand side variables
    external ml_Weight          // Group weights
    
    external ml_draws           // Number of random draws
    external ml_burn            //   Initial draws to burn
    external ml_R               //   Halton sequences
    
    external ml_Rvars           // Random coefficients
    external ml_corr            //   Enable correlation?
    
    external ml_heckm           // Joint wage estimation?
    external ml_HeckmVars       //   Right hand side variables
    external ml_SelectVars      //   Selection variables
    
    external ml_wagep           // Wage Prediction Error?
    external ml_Wpred           //   Prediction dummies
    external ml_Days            //   Number of days per tax year
    external ml_Hwage           //   Hourly wage rates
    external ml_Sigma           //   Variance of the wage regression
    external ml_Hours           //   Hours of work
    
    external ml_TaxregB         // Tax Regression
    external ml_TaxregVars      //   Wage independent variables of tax regression
    external ml_TaxregIas1      //   Wage interaction variables of tax regression
    external ml_TaxregIas2      //   Wage interaction variables of tax regression
    
    external ml_round           // To round, or not to round.
    
    external ml_C
    external ml_CX
    external ml_C2X
    external ml_L1
    external ml_LX1
    external ml_L2X1
    external ml_L2
    external ml_LX2
    external ml_L2X2
    external ml_Xind
    
    
    //ml_Y = moptimize_util_depvar(ML, 1)     // Left hand side variable
    
    
    /* Setup */
    
    // Definitions
    i     = 1                                       // Indicates first observation of active group
    nRV   = 1                                       // Indicates next random variable to use (column of ml_R)
    rvars = rows(ml_Rvars)                          // Number of random variables
    nobs  = rows(ml_Y)                              // Number of observations
    nlei  = cols(ml_L1) + cols(ml_L2)               // Number of leisure terms
    ncons = cols(ml_CX) + cols(ml_C2X) + 2 + nlei   // Number of variables including consumption
    
    // Number of coefficients
    b     = cols(B)                                             // Total number
    brnd  = (ml_corr  == 1 ? rvars * (rvars + 1) / 2 : rvars)   // Number of variance and covariance terms for random coefficients
    bheck = cols(ml_HeckmVars)                                  // Number of Heckman wage regression coefficients
    bsel  = cols(ml_SelectVars)                                 // Number of wage selection coefficients (+ rho)
    bfix  = b - brnd - bheck - bsel - 2 * (bsel > 0)            // Number of fix preference coefficients
    
    // Maximum Likelihood Parameter
    lnf = 0             // Log-likelihood
    G   = J(1, b, 0)    // Gradient
    H   = J(b, b, 0)    // Hessian matrix
    
    // Build coefficient vector
    Bfix  = B[|1,1\1,bfix|]                                                             // Get fixed coefficients
    Brnd  = (rvars > 0 ? B[|1,bfix + 1\1,bfix + brnd|] : J(0, 0, 0))                    // Get auxiliary random coefficients
    Sigm  = (ml_corr == 1 ? lowertriangle(invvech(Brnd')) : diag(Brnd'))                // Build variance-(covariance) matrix
    Bheck = (bheck > 0 ? B[|1,bfix + brnd + 1\1,bfix + brnd + bheck|] : J(0, 0, 0))     // Wage coefficients
    Bsel  = (bsel  > 0 ? B[|1,bfix + brnd + bheck + 1\1,b - 2|] : J(0, 0, 0))           // Selection coefficients
    
    //HeckRho = (bsel > 0 ? (exp(2 :* B[1,b - 1]) :- 1) / (exp(2 :* B[1,b - 1]) :+ 1) : J(0, 0, 0))       // Heckman rho
    //HeckSig = (bsel > 0 ? exp(B[1,b]) : J(0, 0, 0))                                                     // Heckman sigma (lnSig)
    HeckRho = (bsel > 0 ? B[1,b - 1] : J(0, 0, 0))      // Heckman rho
    HeckSig = (bsel > 0 ? B[1,b]     : J(0, 0, 0))      // Heckman sigma (lnSig)
    
    // Build matrix with random coefficients (mean zero), every row is a draw
    if (brnd > 0) {
        Brnd = J(rows(ml_R), cols(Bfix), 0)
        for (rv = 1; rv <= rvars; rv++) {
            if (ml_corr == 0) Brnd[.,ml_Rvars[rv,1]] = ml_R[.,rv] :* Sigm[rv,rv]
            else {
                for (rv2 = rv; rv2 <= rvars; rv2++) {
                    Brnd[.,ml_Rvars[rv2,1]] = Brnd[.,ml_Rvars[rv2,1]] + ml_R[.,rv] :* Sigm[rv2,rv]
                }
            }
            nRV = nRV + 1
        }
    }
    // From now on: Beta[rows=ml_R,cols=Bfix] = Bfix :+ Brnd
    
    // Calculate dude share
    if (ml_heckm == 0 & ml_wagep == 0 & ml_corr == 0) {
        DUdC = cross((ml_CX, J(nobs, 1, 1), (ml_C2X, J(nobs, 1, 1)) :* 2 :* ml_C, ml_L1, ml_L2)', Bfix[|1,1\1,ncons|]')
        if (brnd > 0) dudes = 1 - colsum(normal(DUdC :/ sqrt(colsum((ml_Rvars :<= ncons) :* diagonal(Sigm:^2)))) :/ nobs)
        else          dudes = colsum(DUdC :< 0) / nobs
        st_numscalar("r(dudes)", dudes)
    }
    
    // Predict wages
    if (ml_heckm == 1) {
        // Selection equation
        if (bsel > 0) {
            Select = cross(ml_SelectVars', Bsel')                       // Selection prediction
            SelRes = ml_Y :* ((ml_Hwage :< .) :- Select)                //   Selection residuals
            SelSig = sqrt(cross(SelRes, SelRes) / (ml_groups - bsel))   //   Selection RMSE
            Lambda = normalden(Select:/SelSig):/normal(Select:/SelSig)  //   Heckman lambda
        } else Lambda = J(nobs, 0, 0)
        
        // Predict log-wages
        Hwage = cross((ml_HeckmVars, Lambda)', (Bheck, HeckRho :* HeckSig)')
        
        if (bsel > 0) {
            Hwage = exp(Hwage :+ HeckSig^2/2)       // Predict wages
        } else {
            Hwres   = ml_Y :* (log(ml_Hwage) :- Hwage)                  // Residuals
            HeckSig = sqrt(cross(Hwres, Hwres)/(ml_groups - bheck))     // RMSE
            Hwage   = exp(Hwage :+ HeckSig^2/2)                         // Predict wages
            for (c = 1; c <= cols(HeckSig); c++) {                      // Save RMSE
                printf("sigma_w" + strofreal(c) + "=" + strofreal(HeckSig[1,c]) + "\n");
                st_numscalar("r(sigma_w" + strofreal(c) + ")", HeckSig[1,c])
            }
        }
        
        //printf("SelSig = " + strofreal(SelSig) + ", HeckRho = " + strofreal(B[1,b - 1]) + "/" + strofreal(HeckRho) + ", HeckSig = " + strofreal(B[1,b]) + "/" + strofreal(HeckSig) + "\n");
    } else {
        Hwage   = ml_Hwage
        HeckSig = ml_Sigma
    }
    // Round wage rates?
    if (ml_round == 1 & cols(Hwage) > 0) Hwage = round(Hwage, 0.01)
    
    
    /* Loop over households */
    
    for (n = 1; n <= ml_groups; n++) {
        // Last observation of group n
        c   = ml_J[i,1]
        e   = i + c - 1
        Yn  = ml_Y[|i,1\e,1|]
        Xnr = ml_X[|i,1\e,.|]

        // Fetch right hand side parts if needed
        if (ml_wagep == 1 | ml_heckm == 1) {
            C    =  ml_C[|i,1\e,1|]   // Get consumption from data
            CX   = (cols(ml_CX)   > 0 ?   ml_CX[|i,1\e,.|] : J(c, 0, 0))
            C2X  = (cols(ml_C2X)  > 0 ?  ml_C2X[|i,1\e,.|] : J(c, 0, 0))
            L1   = ml_L1[|i,1\e,1|]
            LX1  = (cols(ml_LX1)  > 0 ?  ml_LX1[|i,1\e,.|] : J(c, 0, 0))
            L2X1 = (cols(ml_L2X1) > 0 ? ml_L2X1[|i,1\e,.|] : J(c, 0, 0))
            L2   = (cols(ml_L2)   > 0 ?   ml_L2[|i,1\e,1|] : J(c, 0, 0))
            LX2  = (cols(ml_LX2)  > 0 ?  ml_LX2[|i,1\e,.|] : J(c, 0, 0))
            L2X2 = (cols(ml_L2X2) > 0 ? ml_L2X2[|i,1\e,.|] : J(c, 0, 0))
            Xind = (cols(ml_Xind) > 0 ? ml_Xind[|i,1\e,.|] : J(c, 0, 0))
            //Wn   = J(c, cols(Hwage), 1) :* cross(Yn, Hwage[|i,1\e,.|])
            Wn   = Hwage[|i,1\e,.|]
        }

        // Sum over draws
        lsum = 0
        Gsum = J(1, b, 0)
        if (ml_draws == 1 & 1 == 0) Hsum = J(b, b, 0)
        else {
            H1sum = J(1, b, 0)
            H2sum = J(b, b, 0)
        }

        // Run by random draw
        for (r = 1; r <= ml_draws; r++) {
            // Init
            iRV = ml_draws * (n - 1) + r    // Indicates the active Halton sequence


            /* Integrate out wage prediction error */

            if (ml_wagep == 1 | ml_heckm == 1) {
                //
                // Calculate monthly earnings
                //

                // Adjust wages with random draws if prediction enabled
                if (ml_wagep == 1) Wn = Wn :* exp(cross(HeckSig' :* ml_R[|iRV,nRV\iRV,.|]', ml_Wpred[|i,1\e,.|]'))'

                // Calculate monthly earnings
                Mwage = (ml_Days[|i,1\e,1|] :/ 12 :/ 7) :* ml_Hours[|i,1\e,.|] :* Wn

                // Round monthly earnings if enabled
                if (ml_round == 1) Mwage = round(Mwage, 0.01)

                //
                // Predict disposable income
                //

                // Container with independent variables for dpi prediction
                TaxregX = J(c, 0, 0)

                // Fill matrix of independent variables for dpi prediction
                for (s = 1; s <= nlei; s++) {
                    TaxregX = (TaxregX, Mwage[.,s], Mwage[.,s]:^2)
                    if      (s == 1) TaxregX = (TaxregX, Mwage[.,s] :* ml_TaxregIas1[|i,1\e,.|], Mwage[.,s]:^2 :* ml_TaxregIas1[|i,1\e,.|])
                    else if (s == 2) TaxregX = (TaxregX, Mwage[.,s] :* ml_TaxregIas2[|i,1\e,.|], Mwage[.,s]:^2 :* ml_TaxregIas2[|i,1\e,.|])
                }
                TaxregX = (TaxregX, ml_TaxregVars[|i,1\e,.|], J(c, 1, 1))

                // Predict disposable income (can't be negative!)
                C = rowmax((cross(TaxregX', ml_TaxregB'), J(c, 1, 1)))

                // Build matrix with independent variables
                if      (ml_ufunc == "tran") Xnr = (log(C)  :* (CX,  J(c, 1, 1), log(C) :*C2X,  log(C),  log(L2)),
                                                    log(L1) :* (LX1, J(c, 1, 1), log(L1):*L2X1, log(L1)),
                                                    log(L2) :* (LX2, J(c, 1, 1), log(L2):*L2X2, log(L2)), log(L1):*log(L2), Xind)
                else if (ml_ufunc == "quad") Xnr = (C  :* (CX,  J(c, 1, 1), C :*C2X,  C,   L1, L2),
                                                    L1 :* (LX1, J(c, 1, 1), L1:*L2X1, L1),
                                                    L2 :* (LX2, J(c, 1, 1), L2:*L2X2, L2), L1:*L2, Xind)
            }


            /* Calculate utility levels */

            // Build (random?) coefficients matrix
            Beta = Bfix :+ (brnd > 0 ? Brnd[iRV,.] : 0)

            // Calculate choice probabilities
            Unr = cross(Xnr', Beta')                                    // Utility (choices in rows, draws in columns)
            Enr = exp(Unr :+ colmin(-mean(Unr) \ 700 :- colmax(Unr)))   // Standardize to avoid missings
            Pnr = Enr :/ colsum(Enr)                                    // Probabilities

            // Simplify
            pni  = cross(Yn, Pnr)   // Probability that choice is chosen
            YmPn = Yn :- Pnr        // Choice minus probabilities
            PXn  = cross(Pnr, Xnr)  // Right hand side cross by probs
            YXn  = cross(Yn, Xnr)   // Right hand side cross by choice


            /* Add to sum over draws */

            // Add to likelihood
            lsum = lsum + pni

            // Calculate gradient vector
            if (todo >= 1) {
                // Calculate gradient
                DUdB = Xnr
                
                // Utility
                Gnr = pni * colsum(YmPn :* DUdB)

                // Random components
                if (brnd > 0) {
                    for (rv = 1; rv <= rvars; rv++) {
                        nCols = (ml_corr == 1 ? rvars - rv + 1 : 1)
                        Gnr   = (Gnr, pni * cross(YmPn, DUdB[.,ml_Rvars[|rv,1\rv+nCols-1,1|]]) * ml_R[iRV,rv])
                    }
                }
                
                // Heckman?
                if (ml_heckm == 1) {
                    DUdC  = cross((CX, J(c, 1, 1), (C2X, J(c, 1, 1)) :* 2 :* C, L1, L2)', Beta[|1,1\1,ncons|]')
                    DCdM  = cross((J(c, 1, 1), 2 :* Mwage, ml_TaxregIas1[|i,1\e,.|], 2 :* Mwage :* ml_TaxregIas1[|i,1\e,.|])', ml_TaxregB[|1,1\1,2 + 2 * cols(ml_TaxregIas1)|]')
                    DMdH  = (ml_Days[|i,1\e,1|] :/ 12 :/ 7) :* ml_Hours[|i,1\e,.|]
                    DHdB  = Wn :* (ml_HeckmVars[|i,1\e,.|] :- colsum(ml_HeckmVars :* Hwres) / (ml_groups - bheck))
                    DUdBw = DUdC :* DCdM :* DMdH :* DHdB
                    Gnr   = (Gnr, pni * colsum(YmPn :* DUdBw))
                }

                // Total
                Gsum = Gsum + Gnr
            }

            // Calculate Hessian matrix
            if (todo == 2) {
                if (ml_draws == 1 & 1 == 0) Hsum = Hsum - cross(Pnr :* Xnr, Xnr :- PXn)
                else {
                    // Utility
                    H1 = - pni :* (YXn - PXn)
                    H2 =   pni :* (cross(YXn - PXn, cross(YmPn, Xnr)) - cross(Pnr :* Xnr, Xnr :- PXn))
                    
                    // Random components
                    S1   = J(1, 0, 0)
                    S2xx = (brnd > 0 ? J((ml_corr == 1 ? brnd : 0), (ml_corr == 1 ? brnd : 1), 0) : J(0, 0, 0))
                    S2xy = J(0, cols(H2), 0)
                    if (brnd > 0) {
                        if (ml_corr == 1) {
                            iCol = 1
                            for (rv = 1; rv <= rvars; rv++) {
                                nCols = rvars - rv + 1
                                iRow = iCol
                                for (rv2 = rv; rv2 <= rvars; rv2++) {
                                    nRows = rvars - rv2 + 1
                                    S1   = S1,   - pni :*  (YXn[.,ml_Rvars[rv2,1]] - PXn[.,ml_Rvars[rv2,1]])  * ml_R[iRV,rv]
                                    S2xy = S2xy \  pni :* (cross(YXn[.,ml_Rvars[rv2,1]]                  - PXn[.,ml_Rvars[rv2,1]],                 cross(YmPn, Xnr)) -
                                                           cross(Xnr[.,ml_Rvars[rv2,1]]                 :- PXn[.,ml_Rvars[rv2,1]], (Pnr :* Xnr))) * ml_R[iRV,rv]
                                    Svar =         pni :* (cross(YXn[.,ml_Rvars[|rv2,1\rv2+nRows-1,1|]] :- PXn[.,ml_Rvars[|rv2,1\rv2+nRows-1,1|]], cross(YmPn, Xnr[.,ml_Rvars[|rv,1\rv+nCols-1,1|]])) -
                                                           cross(Xnr[.,ml_Rvars[|rv2,1\rv2+nRows-1,1|]] :- PXn[.,ml_Rvars[|rv2,1\rv2+nRows-1,1|]],      Pnr :* Xnr[.,ml_Rvars[|rv,1\rv+nCols-1,1|]])) *
                                                        ml_R[iRV,rv] * ml_R[iRV,rv2]
                                    S2xx[|iRow,iCol\iRow+nRows-1,iCol+nCols-1|] = Svar
                                    if (iRow != iCol) S2xx[|iCol,iRow\iCol+nCols-1,iRow+nRows-1|] = Svar'
                                    iRow = iRow + nRows
                                }
                                iCol = iCol + nCols
                            }
                        } else {
                            for (rv = 1; rv <= rvars; rv++) {
                                S1   = S1,      - pni :*       (YXn[.,ml_Rvars[rv,1]] - PXn[.,ml_Rvars[rv,1]]) * ml_R[iRV,rv]
                                S2xy = S2xy \     pni :* (cross(YXn[.,ml_Rvars[rv,1]] - PXn[.,ml_Rvars[rv,1]], cross(YmPn, Xnr))                    - cross(Xnr[.,ml_Rvars[rv,1]] :- PXn[.,ml_Rvars[rv,1]], Pnr :* Xnr)) * ml_R[iRV,rv]
                                S2xx = S2xx \     pni :* (cross(YXn[.,ml_Rvars[rv,1]] - PXn[.,ml_Rvars[rv,1]], cross(YmPn, Xnr[.,ml_Rvars[rv,1]]))  - cross(Xnr[.,ml_Rvars[rv,1]] :- PXn[.,ml_Rvars[rv,1]], Pnr :* Xnr[.,ml_Rvars[rv,1]])) * ml_R[iRV,rv]:^2
                                for (rv2 = rv + 1; rv2 <= rvars; rv2++) {
                                    S2xx = S2xx \ pni :* (cross(YXn[.,ml_Rvars[rv,1]] - PXn[.,ml_Rvars[rv,1]], cross(YmPn, Xnr[.,ml_Rvars[rv2,1]])) - cross(Xnr[.,ml_Rvars[rv,1]] :- PXn[.,ml_Rvars[rv,1]], Pnr :* Xnr[.,ml_Rvars[rv2,1]])) * ml_R[iRV,rv] * ml_R[iRV,rv2]
                                }
                            }
                            S2xx = invvech(S2xx)
                        }
                        
                        H2sum = H2sum + (H2, S2xy' \ S2xy, S2xx)
                    }

                    // Heckman
                    W1   = J(1, 0, 0)
                    W2xy = J(0, bfix, 0)
                    W2xx = J(0, 0, 0)
                    if (ml_heckm == 1) {
                        DXdH   = (CX, J(c, 1, 1), (C2X, J(c, 1, 1)) :* 2 :* C, L1, J(c, cols(Xnr) - (cols(CX) + cols(C2X) + 2 + nlei), 0)) :*
                                 ((J(c, 1, 1), 2 :* Mwage, ml_TaxregIas1[|i,1\e,.|], 2 :* Mwage :* ml_TaxregIas1[|i,1\e,.|]) * ml_TaxregB[|1,1\1,2 + 2 * cols(ml_TaxregIas1)|]') :*
                                 (ml_Days[|i,1\e,1|] :/ 12 :/ 7) :* ml_Hours[|i,1\e,.|]
                        D2UdC2 = 2 * Beta[|1,cols(CX) + 2\1,cols(CX) + cols(C2X) + 2|]
                        D2CdM2 = cross((J(c, 1, 2), 2 :* ml_TaxregIas1[|i,1\e,.|])', (ml_TaxregB[1,2], ml_TaxregB[|1,2 + cols(ml_TaxregIas1) + 1\1,2 + 2 * cols(ml_TaxregIas1)|])')
                        D2MdH2 = 0
                        
                        YmPnD2UdBw2 = cross(YmPn :* DHdB :* (DMdH:^2 :* (D2UdC2 :* DCdM:^2 :+ DUdC :* D2CdM2) + DUdC :* DCdM :* D2MdH2), DHdB)
                        for (hv = 1; hv <= bheck; hv++) {
                            YmPnD2UdBw2[hv,.] = YmPnD2UdBw2[hv,.] + cross(YmPn :* DUdC :* DCdM :* DMdH, DHdB :* (ml_HeckmVars[|i,hv\e,hv|] :- colsum(ml_HeckmVars[.,hv] :* Hwres) / (ml_groups - bheck)) :+
                                                                                                        cross(Wn', cross(ml_Y :* ml_HeckmVars[.,hv], ml_HeckmVars) :/ (ml_groups - bheck)))
                        }
                        
                        W1   = - pni :* (cross(Yn, DUdBw) - cross(Pnr, DUdBw))
                        W2xy =   pni :* (cross(cross(Yn, DUdBw) - cross(Pnr, DUdBw), cross(YmPn, Xnr)) -
                                         cross(DUdBw :- cross(Pnr, DUdBw), Pnr :* Xnr) +
                                         cross(YmPn :* DXdH, /*Wn :* ml_HeckmVars[|i,1\e,.|]*/DHdB)')
                        W2xx =   pni :* (cross(cross(Yn, DUdBw) - cross(Pnr, DUdBw), cross(YmPn, DUdBw)) -
                                         cross(DUdBw :- cross(Pnr, DUdBw), Pnr :* DUdBw) + YmPnD2UdBw2)
                        
                        //WSxy = J(0, 0, 0)
                        H2sum = H2sum + (H2, /*S2xy',*/ W2xy' \ /*S2xy, S2xx, WSxy' \ */W2xy, /*WSxy, */W2xx)
                    }

                    // Total
                    H1sum = H1sum + (H1, S1, W1)
                    if (brnd == 0 & ml_heckm == 0) H2sum = H2sum + H2
                    //H2sum = H2sum + (H2, /*S2xy',*/ W2xy' \ /*S2xy, S2xx, WSxy' \ */W2xy, /*WSxy, */W2xx)
                    //H2sum = H2sum + (H2, S2xy' \ S2xy, S2xx)
                }
            }

        }

        // Prevent likelihood from becoming exactly zero
        lsum = max((lsum, 1e-25))

        // Add to overall statistics
        lnf = lnf + ml_Weight[i,1] * log(lsum / ml_draws)
        if (todo >= 1) G = G + ml_Weight[i,1] * (lsum > 1e-25 ? Gsum / lsum : J(1, cols(G), 0))
        if (todo == 2) H = H + ml_Weight[i,1] * (lsum > 1e-25 ? (ml_draws == 1 & 1 == 0 ? Hsum : cross(Gsum, H1sum) / lsum^2 + H2sum / lsum) : J(rows(H), cols(H), 0))

        // Next household
        i = i + c
    }
    //lnf
}
end

***
