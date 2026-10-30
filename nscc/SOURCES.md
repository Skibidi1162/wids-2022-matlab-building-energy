# Official sources checked 30 October 2026

These documents guide the templates; they do not establish this user's live account, software licenses, or allocation. No NSCC host was contacted.

| Source | Used for |
|---|---|
| [NSCC: Submit a Batch Job](https://nsccsg.github.io/quickstart/submit-a-batch-job/) | PBS Pro; `qsub`, project/queue/resource directives; `qstat` |
| [NSCC: Launch an Interactive Job](https://nsccsg.github.io/quickstart/launch-an-interactive-job/) | Compute-node workflow; CPU/GPU allocation examples are system-specific |
| [NSCC: Connect to the Systems](https://nsccsg.github.io/quickstart/connect-to-the-systems/) | Multiple NSCC systems exist; hostname must be identified |
| [NSCC: ASPIRE 2A FAQ](https://help.nscc.sg/aspire2a/faqs/) | Routing queues, AI queue access, module discovery, login-node restrictions |
| [NSCC: ASPIRE 2A software list, updated 6 January 2026](https://help.nscc.sg/wp-content/uploads/2512-SoftwareList-2A.pdf) | Published MATLAB entries are Runtime modules; discover the actual full installation separately |
| [NSCC: ASPIRE 2A system specifications](https://nsccsg.github.io/systems/aspire2a/system-specifications/) | CPU/GPU queues and durable versus temporary storage |
| [NSCC: ASPIRE 2A+ changes effective 2 June 2025](https://help.nscc.sg/aspire2aplus/urgent-scheduled-maintenance-for-aspire-2a-on-22-january-2025-9am-to-6-30pm-2-2-2-2-2-3-3-2/) | Queue changes demonstrate why ASPIRE 2A settings must not be assumed for another system |
| [MathWorks: MATLAB Runtime](https://www.mathworks.com/products/compiler/matlab-runtime.html) | Runtime executes compiled applications; it is not the full interpreter needed here |
| [MathWorks: fitrensemble](https://www.mathworks.com/help/stats/fitrensemble.html) | Bagging/random-predictor forests and CPU options; GPU bagging is unsupported |
| [MathWorks: templateTree](https://www.mathworks.com/help/stats/templatetree.html) | Leaf/split/mtry settings and reproducible random predictor selection |
| [MathWorks: fitrkernel](https://www.mathworks.com/help/stats/fitrkernel.html) | Approximate Gaussian random feature regression, least-squares learner, expansion/block limits; GPU since R2025a |
| [MathWorks: fitrnet](https://www.mathworks.com/help/stats/fitrnet.html) | Regularized neural regression, fixed iteration/convergence diagnostics; GPU since R2024b |
| [MathWorks: fitrlinear](https://www.mathworks.com/help/stats/fitrlinear.html) | Regularized least-squares reference and LBFGS iteration control |

Current documentation can describe features absent in older installed releases. This package chooses a conservative R2023b+ CPU interface and verifies it on the actual compute node before model jobs. No GPU launch profile is provided. NSCC sources contain differing GPU ratios and evolving queue descriptions; no GPU memory/core ratio is embedded in the package.
