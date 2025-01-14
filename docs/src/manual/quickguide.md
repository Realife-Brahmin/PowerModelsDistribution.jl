# Quick Start Guide

Once PowerModelsDistribution is installed, Ipopt is installed, and a network data file (_e.g._, `"case3_unbalanced.dss"` in the package folder under `./test/data`) has been acquired, an unbalanced AC Optimal Power Flow can be executed with,

```julia
using PowerModelsDistribution
using Ipopt

pkgdir = dirname(dirname(pathof(PowerModelsDistribution)));
casefolder = joinpath(pkgdir, "test", "data", "opendss");
casename = "case3_unbalanced.dss";
casefile = joinpath(casefolder, casename);
solve_mc_opf(casefile, ACPUPowerModel, Ipopt.Optimizer);
```

## Parsing files

To parse an OpenDSS file into PowerModelsDistribution's default [`ENGINEERING`](@ref ENGINEERING) format, use the [`parse_file`](@ref parse_file) command

```julia
eng = parse_file("case3_unbalanced.dss")
```

To examine the [`MATHEMATICAL`](@ref MATHEMATICAL) model it is possible to transform the data model using the [`transform_data_model`](@ref transform_data_model) command, but this step is not necessary to run a problem.

```julia
math = transform_data_model(eng)
```

## Getting Results

The run commands in PowerModelsDistribution return detailed results data in the form of a dictionary. This dictionary can be saved for further processing as follows,

```julia
result = solve_mc_opf(eng, ACPUPowerModel, Ipopt.Optimizer)
```

Alternatively, you can pass the file path string directly:

```julia
result = solve_mc_opf("case3_unbalanced.dss", ACPUPowerModel, Ipopt.Optimizer)
```

## Accessing Different Formulations

[`ACPUPowerModel`](@ref ACPUPowerModel) indicates an unbalanced (_i.e._, multiconductor) AC formulation in polar coordinates.  This more generic [`solve_mc_opf`](@ref solve_mc_opf) allows one to solve an OPF problem with any power network formulation in PowerModelsDistribution.  For example, the [`SDPUBFPowerModel`](@ref SDPUBFPowerModel) relaxation of unbalanced Optimal Power Flow (branch flow model) can be run with,

```julia
using SCS
solve_mc_opf(eng, SDPUBFPowerModel, with_optimizer(SCS.Optimizer))
```

Note that you have to use a SDP-capable solver, _e.g._, the open-source solver SCS, to solve SDP models.

## Inspecting the Formulation

The following example demonstrates how to break a [`solve_mc_opf`](@ref solve_mc_opf) call into separate model building and solving steps.  This allows inspection of the JuMP model created by PowerModelsDistribution for the AC-OPF problem. Note that the [`MATHEMATICAL`](@ref MATHEMATICAL) model must be passed to [`instantiate_mc_model`](@ref instantiate_mc_model), so the data model must either be transformed with [`transform_data_model`](@ref transform_data_model) or parsed directly to a [`MATHEMATICAL`](@ref MATHEMATICAL) model using the `data_model` keyword argument:

```julia
math = parse_file("case3_unbalanced.dss"; data_model=MATHEMATICAL)
pm = instantiate_model(math, ACPUPowerModel, build_mc_opf; ref_extensions=[ref_add_arcs_trans!])
print(pm.model)
optimize_model!(pm, optimizer=Ipopt.Optimizer)
```

## Providing a Warm Start

To reduce the number of solver iterations, it might be useful to provide a (good) initial value to some or all optimization variables. To do so, it is sufficient to assign a value or vector (depending on the dimensions of the variable) in the data dictionary, under the key `$(variablename)_start`. The example below shows how to do it for the `vm` and `va` variables.

```julia
math = parse_file("case3_unbalanced.dss"; data_model=MATHEMATICAL)
math["bus"]["2"]["vm_start"] = [0.9959, 0.9959, 0.9959]
math["bus"]["2"]["va_start"] = [0.00, -2.0944, 2.0944]
```

Providing a bad initial value might result in the opposite effect: longer calculation times or convergence issues, so the start value assignment should be done attentively.
If no initial value is provided, a flat start is assigned by default. The default initial value of each variable is indicated in the function where the variable is defined, as the last argument of the [`comp_start_value`](@ref comp_start_value) function. In the case of `vm`, this is 1.0, as shown below:

```julia
vm = var(pm, nw)[:vm] = Dict(i => JuMP.@variable(pm.model,
        [c in 1:ncnds], base_name="$(nw)_vm_$(i)",
        start = comp_start_value(ref(pm, nw, :bus, i), "vm_start", c, 1.0)
    ) for i in ids(pm, nw, :bus)
)
```

Finally, it should be noted that if `va_start` and `vm_start` are present in a data dictionary which is passed to the ACR or IVR formulation, these are converted to their rectangular equivalents and used as `vr_start` and `vi_start`.

## Examples

More examples of working with the engineering data model can be found in the `/examples` folder of the PowerModelsDistribution.jl repository. These are Pluto Notebooks; instructions for running them can be found in the [Pluto documentation](https://github.com/fonsp/Pluto.jl#readme).
