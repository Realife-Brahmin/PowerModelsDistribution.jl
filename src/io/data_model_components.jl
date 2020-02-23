#TODO
# Can buses in a voltage zone have different terminals?
# Add current/power bounds to data model


function copy_kwargs_to_dict_if_present!(dict, kwargs, args)
    for arg in args
        if haskey(kwargs, arg)
            dict[string(arg)] = kwargs[arg]
        end
    end
end

function add_kwarg!(dict, kwargs, name, default)
    if haskey(kwargs, name)
        dict[string(name)] = kwargs[name]
    else
        dict[string(name)] = default
    end
end

function component_dict_from_list!(list)
    dict = Dict{String, Any}()
    for comp_dict in list
        dict[comp_dict["id"]] = comp_dict
    end
    return dict
end

REQUIRED_FIELDS = Dict{Symbol, Any}()
DTYPES = Dict{Symbol, Any}()
CHECKS = Dict{Symbol, Any}()

function check_dtypes(dict, dtypes, comp_type, id)
    for key in keys(dict)
        symb = Symbol(key)
        if haskey(dtypes, symb)
            @assert(isa(dict[key], dtypes[symb]), "$comp_type $id: the property $key should be a $(dtypes[symb]), not a $(typeof(dict[key])).")
        else
            #@assert(false, "$comp_type $id: the property $key is unknown.")
        end
    end
end


function add!(data_model, comp_type, comp_dict)
    @assert(haskey(comp_dict, "id"), "The component does not have an id defined.")
    id = comp_dict["id"]
    if !haskey(data_model, comp_type)
        data_model[comp_type] = Dict{Any, Any}()
    else
        @assert(!haskey(data_model[comp_type], id), "There is already a $comp_type with id $id.")
    end
    data_model[comp_type][id] = comp_dict
end

function _add_unused_kwargs!(comp_dict, kwargs)
    for (prop, val) in kwargs
        if !haskey(comp_dict, "$prop")
            comp_dict["$prop"] = val
        end
    end
end

function check_data_model(data)
    for component in keys(DTYPES)
        if haskey(data, string(component))
            for (id, comp_dict) in data[string(component)]
                if haskey(REQUIRED_FIELDS, component)
                    for field in REQUIRED_FIELDS[component]
                        @assert(haskey(comp_dict, string(field)), "The property \'$field\' is missing for $component $id.")
                    end
                end
                if haskey(DTYPES, component)
                    check_dtypes(comp_dict, DTYPES[component], component, id)
                end
                if haskey(CHECKS, component)
                    CHECKS[component](data, comp_dict)
                end
            end
        end
    end
end


function create_data_model(; kwargs...)
    data_model = Dict{String, Any}("settings"=>Dict{String, Any}())

    add_kwarg!(data_model["settings"], kwargs, :v_var_scalar, 1E3)

    _add_unused_kwargs!(data_model["settings"], kwargs)

    return data_model
end

# COMPONENTS
#*#################

DTYPES[:ev] = Dict()
DTYPES[:storage] = Dict()
DTYPES[:pv] = Dict()
DTYPES[:wind] = Dict()
DTYPES[:switch] = Dict()
DTYPES[:shunt] = Dict()
DTYPES[:autotransformer] = Dict()
DTYPES[:synchronous_generator] = Dict()
DTYPES[:zip_load] = Dict()
DTYPES[:grounding] = Dict(
    :bus => Any,
    :rg => Real,
    :xg => Real,
)
DTYPES[:synchronous_generator] = Dict()
DTYPES[:boundary] = Dict()
DTYPES[:meter] = Dict()


function _check_same_size(data, keys; context=missing)
    size_comp = size(data[string(keys[1])])
    for key in keys[2:end]
        @assert(all(size(data[string(key)]).==size_comp), "$context: the property $key should have the same size as $(keys[1]).")
    end
end


function _check_has_size(data, keys, size_comp; context=missing, allow_missing=true)
    for key in keys
        if haskey(data, key) || !allow_missing
            @assert(all(size(data[string(key)]).==size_comp), "$context: the property $key should have as size $size_comp.")
        end
    end
end

function _check_connectivity(data, comp_dict; context=missing)

    if haskey(comp_dict, "f_bus")
        # two-port element
        _check_bus_and_terminals(data, comp_dict["f_bus"], comp_dict["f_connections"], context)
        _check_bus_and_terminals(data, comp_dict["t_bus"], comp_dict["t_connections"], context)
    elseif haskey(comp_dict, "bus")
        if isa(comp_dict["bus"], Vector)
            for i in 1:length(comp_dict["bus"])
                _check_bus_and_terminals(data, comp_dict["bus"][i], comp_dict["connections"][i], context)
            end
        else
            _check_bus_and_terminals(data, comp_dict["bus"], comp_dict["connections"], context)
        end
    end
end


function _check_bus_and_terminals(data, bus_id, terminals, context=missing)
    @assert(haskey(data, "bus") && haskey(data["bus"], bus_id), "$context: the bus $bus_id is not defined.")
    bus = data["bus"][bus_id]
    for t in terminals
        @assert(t in bus["terminals"], "$context: bus $(bus["id"]) does not have terminal \'$t\'.")
    end
end


function _check_has_keys(comp_dict, keys; context=missing)
    for key in keys
        @assert(haskey(comp_dict, key), "$context: the property $key is missing.")
    end
end

function _check_configuration_infer_dim(comp_dict; context=missing)
    conf = comp_dict["configuration"]
    @assert(conf in ["delta", "wye"], "$context: the configuration should be \'delta\' or \'wye\', not \'$conf\'.")
    return conf=="wye" ? length(comp_dict["connections"])-1 : length(comp_dict["connections"])
end


# linecode

DTYPES[:linecode] = Dict(
    :id => Any,
    :rs => Array{<:Real, 2},
    :xs => Array{<:Real, 2},
    :g_fr => Array{<:Real, 2},
    :g_to => Array{<:Real, 2},
    :b_fr => Array{<:Real, 2},
    :b_to => Array{<:Real, 2},
)

REQUIRED_FIELDS[:linecode] = keys(DTYPES[:linecode])

CHECKS[:linecode] = function check_linecode(data, linecode)
    _check_same_size(linecode, [:rs, :xs, :g_fr, :g_to, :b_fr, :b_to])
end

function create_linecode(; kwargs...)
    linecode = Dict{String,Any}()

    n_conductors = 0
    for key in [:rs, :xs, :g_fr, :g_to, :b_fr, :b_to]
        if haskey(kwargs, key)
            n_conductors = size(kwargs[key])[1]
        end
    end
    add_kwarg!(linecode, kwargs, :rs, fill(0.0, n_conductors, n_conductors))
    add_kwarg!(linecode, kwargs, :xs, fill(0.0, n_conductors, n_conductors))
    add_kwarg!(linecode, kwargs, :g_fr, fill(0.0, n_conductors, n_conductors))
    add_kwarg!(linecode, kwargs, :b_fr, fill(0.0, n_conductors, n_conductors))
    add_kwarg!(linecode, kwargs, :g_to, fill(0.0, n_conductors, n_conductors))
    add_kwarg!(linecode, kwargs, :b_to, fill(0.0, n_conductors, n_conductors))

    _add_unused_kwargs!(linecode, kwargs)

    return linecode
end

# line

DTYPES[:line] = Dict(
    :id => Any,
    :status => Int,
    :f_bus => AbstractString,
    :t_bus => AbstractString,
    :f_connections => Vector{<:Int},
    :t_connections => Vector{<:Int},
    :linecode => AbstractString,
    :length => Real,
    :c_rating =>Vector{<:Real},
    :s_rating =>Vector{<:Real},
    :angmin=>Vector{<:Real},
    :angmax=>Vector{<:Real},
    :rs => Array{<:Real, 2},
    :xs => Array{<:Real, 2},
    :g_fr => Array{<:Real, 2},
    :g_to => Array{<:Real, 2},
    :b_fr => Array{<:Real, 2},
    :b_to => Array{<:Real, 2},
)

REQUIRED_FIELDS[:line] = [:id, :status, :f_bus, :f_connections, :t_bus, :t_connections, :linecode, :length]

CHECKS[:line] = function check_line(data, line)
    i = line["id"]

    # for now, always require a line code
    if haskey(line, "linecode")
        # line is defined with a linecode
        @assert(haskey(line, "length"), "line $i: a line defined through a linecode, should have a length property.")

        linecode_id = line["linecode"]
        @assert(haskey(data, "linecode") && haskey(data["linecode"], "$linecode_id"), "line $i: the linecode $linecode_id is not defined.")
        linecode = data["linecode"]["$linecode_id"]

        for key in ["n_conductors", "rs", "xs", "g_fr", "g_to", "b_fr", "b_to"]
            @assert(!haskey(line, key), "line $i: a line with a linecode, should not specify $key; this is already done by the linecode.")
        end

        N = size(linecode["rs"])[1]
        @assert(length(line["f_connections"])==N, "line $i: the number of terminals should match the number of conductors in the linecode.")
        @assert(length(line["t_connections"])==N, "line $i: the number of terminals should match the number of conductors in the linecode.")
    else
        # normal line
        @assert(!haskey(line, "length"), "line $i: length only makes sense for linees defined through linecodes.")
        for key in ["n_conductors", "rs", "xs", "g_fr", "g_to", "b_fr", "b_to"]
            @assert(haskey(line, key), "line $i: a line without linecode, should specify $key.")
        end
    end

    _check_connectivity(data, line, context="line $(line["id"])")
end


function create_line(; kwargs...)
    line = Dict{String,Any}()

    add_kwarg!(line, kwargs, :status, 1)
    add_kwarg!(line, kwargs, :f_connections, collect(1:4))
    add_kwarg!(line, kwargs, :t_connections, collect(1:4))

    N = length(line["f_connections"])
    add_kwarg!(line, kwargs, :angmin, fill(-60/180*pi, N))
    add_kwarg!(line, kwargs, :angmax, fill( 60/180*pi, N))

    # if no linecode, then populate loss parameters with zero
    if !haskey(kwargs, :linecode)
        n_conductors = 0
        for key in [:rs, :xs, :g_fr, :g_to, :b_fr, :b_to]
            if haskey(kwargs, key)
                n_conductors = size(kwargs[key])[1]
            end
        end
        add_kwarg!(line, kwargs, :rs, fill(0.0, n_conductors, n_conductors))
        add_kwarg!(line, kwargs, :xs, fill(0.0, n_conductors, n_conductors))
        add_kwarg!(line, kwargs, :g_fr, fill(0.0, n_conductors, n_conductors))
        add_kwarg!(line, kwargs, :b_fr, fill(0.0, n_conductors, n_conductors))
        add_kwarg!(line, kwargs, :g_to, fill(0.0, n_conductors, n_conductors))
        add_kwarg!(line, kwargs, :b_to, fill(0.0, n_conductors, n_conductors))
    end

    _add_unused_kwargs!(line, kwargs)

    return line
end

# Bus

DTYPES[:bus] = Dict(
    :id => Any,
    :status => Int,
    :bus_type => Int,
    :terminals => Array{<:Any},
    :phases => Array{<:Int},
    :neutral => Union{Int, Missing},
    :grounded => Array{<:Any},
    :rg => Array{<:Real},
    :xg => Array{<:Real},
    :vm_pn_min => Real,
    :vm_pn_max => Real,
    :vm_pp_min => Real,
    :vm_pp_max => Real,
    :vm_min => Array{<:Real, 1},
    :vm_max => Array{<:Real, 1},
    :vm_fix => Array{<:Real, 1},
    :va_fix => Array{<:Real, 1},
)

REQUIRED_FIELDS[:bus] = [:id, :status, :terminals, :grounded, :rg, :xg]

CHECKS[:bus] = function check_bus(data, bus)
    id = bus["id"]

    _check_same_size(bus, ["grounded", "rg", "xg"], context="bus $id")

    N = length(bus["terminals"])
    _check_has_size(bus, ["vm_max", "vm_min", "vm", "va"], N, context="bus $id")

    if haskey(bus, "neutral")
        assert(haskey(bus, "phases"), "bus $id: has a neutral, but no phases.")
    end
end

function create_bus(; kwargs...)
    bus = Dict{String,Any}()

    add_kwarg!(bus, kwargs, :status, 1)
    add_kwarg!(bus, kwargs, :terminals, collect(1:4))
    add_kwarg!(bus, kwargs, :grounded, [])
    add_kwarg!(bus, kwargs, :bus_type, 1)
    add_kwarg!(bus, kwargs, :rg, Array{Float64, 1}())
    add_kwarg!(bus, kwargs, :xg, Array{Float64, 1}())

    _add_unused_kwargs!(bus, kwargs)

    return bus
end

# Load

DTYPES[:load] = Dict(
    :id => Any,
    :status => Int,
    :bus => Any,
    :connections => Vector,
    :configuration => String,
    :model => String,
    :pd => Array{<:Real, 1},
    :qd => Array{<:Real, 1},
    :pd_ref => Array{<:Real, 1},
    :qd_ref => Array{<:Real, 1},
    :vnom => Array{<:Real, 1},
    :alpha => Array{<:Real, 1},
    :beta => Array{<:Real, 1},
)

REQUIRED_FIELDS[:load] = [:id, :status, :bus, :connections, :configuration]

CHECKS[:load] = function check_load(data, load)
    id = load["id"]

    N = _check_configuration_infer_dim(load; context="load $id")

    model = load["model"]
    @assert(model in ["constant_power", "constant_impedance", "constant_current", "exponential"])
    if model=="constant_power"
        _check_has_keys(load, ["pd", "qd"], context="load $id, $model:")
        _check_has_size(load, ["pd", "qd"], N, context="load $id, $model:")
    elseif model=="exponential"
        _check_has_keys(load, ["pd_ref", "qd_ref", "vnom", "alpha", "beta"], context="load $id, $model")
        _check_has_size(load, ["pd_ref", "qd_ref", "vnom", "alpha", "beta"], N, context="load $id, $model:")
    else
        _check_has_keys(load, ["pd_ref", "qd_ref", "vnom"], context="load $id, $model")
        _check_has_size(load, ["pd_ref", "qd_ref", "vnom"], N, context="load $id, $model:")
    end

    _check_connectivity(data, load; context="load $id")
end


function create_load(; kwargs...)
    load = Dict{String,Any}()

    add_kwarg!(load, kwargs, :status, 1)
    add_kwarg!(load, kwargs, :configuration, "wye")
    add_kwarg!(load, kwargs, :connections, load["configuration"]=="wye" ? [1, 2, 3, 4] : [1, 2, 3])
    add_kwarg!(load, kwargs, :model, "constant_power")
    if load["model"]=="constant_power"
        add_kwarg!(load, kwargs, :pd, fill(0.0, 3))
        add_kwarg!(load, kwargs, :qd, fill(0.0, 3))
    else
        add_kwarg!(load, kwargs, :pd_ref, fill(0.0, 3))
        add_kwarg!(load, kwargs, :qd_ref, fill(0.0, 3))
    end

    _add_unused_kwargs!(load, kwargs)

    return load
end

# generator

DTYPES[:generator] = Dict(
    :id => Any,
    :status => Int,
    :bus => Any,
    :connections => Vector,
    :configuration => String,
    :cost => Vector{<:Real},
    :pg => Array{<:Real, 1},
    :qg => Array{<:Real, 1},
    :pg_min => Array{<:Real, 1},
    :pg_max => Array{<:Real, 1},
    :qg_min => Array{<:Real, 1},
    :qg_max => Array{<:Real, 1},
)

REQUIRED_FIELDS[:generator] = [:id, :status, :bus, :connections]

CHECKS[:generator] = function check_generator(data, generator)
    id = generator["id"]

    N = _check_configuration_infer_dim(generator; context="generator $id")
    _check_has_size(generator, ["pd", "qd", "pd_min", "pd_max", "qd_min", "qd_max"], N, context="generator $id")

    _check_connectivity(data, generator; context="generator $id")
end

function create_generator(; kwargs...)
    generator = Dict{String,Any}()

    add_kwarg!(generator, kwargs, :status, 1)
    add_kwarg!(generator, kwargs, :configuration, "wye")
    add_kwarg!(generator, kwargs, :cost, [1.0, 0.0]*1E-3)
    add_kwarg!(generator, kwargs, :connections, generator["configuration"]=="wye" ? [1, 2, 3, 4] : [1, 2, 3])

    _add_unused_kwargs!(generator, kwargs)

    return generator
end


# Transformer, n-windings three-phase lossy


DTYPES[:transformer_nw] = Dict(
    :id => Any,
    :status => Int,
    :bus => Array{<:AbstractString, 1},
    :connections => Vector,
    :vnom => Array{<:Real, 1},
    :snom => Array{<:Real, 1},
    :configuration => Array{String, 1},
    :polarity => Array{Bool, 1},
    :xsc => Array{<:Real, 1},
    :rs => Array{<:Real, 1},
    :noloadloss => Real,
    :imag => Real,
    :tm_fix => Array{Array{Bool, 1}, 1},
    :tm => Array{<:Array{<:Real, 1}, 1},
    :tm_min => Array{<:Array{<:Real, 1}, 1},
    :tm_max => Array{<:Array{<:Real, 1}, 1},
    :tm_step => Array{<:Array{<:Real, 1}, 1},
)

REQUIRED_FIELDS[:transformer_nw] = keys(DTYPES[:transformer_nw])


CHECKS[:transformer_nw] = function check_transformer_nw(data, trans)
    id = trans["id"]
    nrw = length(trans["bus"])
    _check_has_size(trans, ["bus", "connections", "vnom", "snom", "configuration", "polarity", "rs", "tm_fix", "tm_set", "tm_min", "tm_max", "tm_step"], nrw, context="trans $id")
    @assert(length(trans["xsc"])==(nrw^2-nrw)/2)

    nphs = []
    for w in 1:nrw
        @assert(trans["configuration"][w] in ["wye", "delta"])
        conf = trans["configuration"][w]
        conns = trans["connections"][w]
        nph = conf=="wye" ? length(conns)-1 : length(conns)
        @assert(all(nph.==nphs), "transformer $id: winding $w has a different number of phases than the previous ones.")
        push!(nphs, nph)
        #TODO check length other properties
    end

    _check_connectivity(data, trans; context="transformer_nw $id")
end


function create_transformer_nw(; kwargs...)
    trans = Dict{String,Any}()

    @assert(haskey(kwargs, :bus), "You have to specify at least the buses.")
    n_windings = length(kwargs[:bus])
    add_kwarg!(trans, kwargs, :status, 1)
    add_kwarg!(trans, kwargs, :configuration, fill("wye", n_windings))
    add_kwarg!(trans, kwargs, :polarity, fill(true, n_windings))
    add_kwarg!(trans, kwargs, :rs, fill(0.0, n_windings))
    add_kwarg!(trans, kwargs, :xsc, fill(0.0, n_windings^2-n_windings))
    add_kwarg!(trans, kwargs, :noloadloss, 0.0)
    add_kwarg!(trans, kwargs, :imag, 0.0)
    add_kwarg!(trans, kwargs, :tm, fill(fill(1.0, 3), n_windings))
    add_kwarg!(trans, kwargs, :tm_min, fill(fill(0.9, 3), n_windings))
    add_kwarg!(trans, kwargs, :tm_max, fill(fill(1.1, 3), n_windings))
    add_kwarg!(trans, kwargs, :tm_step, fill(fill(1/32, 3), n_windings))
    add_kwarg!(trans, kwargs, :tm_fix, fill(fill(true, 3), n_windings))

    _add_unused_kwargs!(trans, kwargs)

    return trans
end

#
# # Transformer, two-winding three-phase
#
# DTYPES[:transformer_2w_ideal] = Dict(
#     :id => Any,
#     :f_bus => String,
#     :t_bus => String,
#     :configuration => String,
#     :f_terminals => Array{Int, 1},
#     :t_terminals => Array{Int, 1},
#     :tm_nom => Real,
#     :tm_set => Real,
#     :tm_min => Real,
#     :tm_max => Real,
#     :tm_step => Real,
#     :tm_fix => Real,
# )
#
#
# CHECKS[:transformer_2w_ideal] = function check_transformer_2w_ideal(data, trans)
# end
#
#
# function create_transformer_2w_ideal(id, f_bus, t_bus, tm_nom; kwargs...)
#     trans = Dict{String,Any}()
#     trans["id"] = id
#     trans["f_bus"] = f_bus
#     trans["t_bus"] = t_bus
#     trans["tm_nom"] = tm_nom
#     add_kwarg!(trans, kwargs, :configuration, "wye")
#     add_kwarg!(trans, kwargs, :f_terminals, trans["configuration"]=="wye" ? [1, 2, 3, 4] : [1, 2, 3])
#     add_kwarg!(trans, kwargs, :t_terminals, [1, 2, 3, 4])
#     add_kwarg!(trans, kwargs, :tm_set, 1.0)
#     add_kwarg!(trans, kwargs, :tm_min, 0.9)
#     add_kwarg!(trans, kwargs, :tm_max, 1.1)
#     add_kwarg!(trans, kwargs, :tm_step, 1/32)
#     add_kwarg!(trans, kwargs, :tm_fix, true)
#     return trans
# end


# Capacitor

DTYPES[:capacitor] = Dict(
    :id => Any,
    :status => Int,
    :bus => Any,
    :connections => Vector,
    :configuration => String,
    :qd_ref => Array{<:Real, 1},
    :vnom => Real,
)

REQUIRED_FIELDS[:capacitor] = keys(DTYPES[:capacitor])


CHECKS[:capacitor] = function check_capacitor(data, cap)
    id = cap["id"]
    N = length(cap["connections"])
    config = cap["configuration"]
    if config=="wye"
        @assert(length(cap["qd_ref"])==N-1, "capacitor $id: qd_ref should have $(N-1) elements.")
    else
        @assert(length(cap["qd_ref"])==N, "capacitor $id: qd_ref should have $N elements.")
    end
    @assert(config in ["delta", "wye", "wye-grounded", "wye-floating"])
    if config=="delta"
        @assert(N>=3, "Capacitor $id: delta-connected capacitors should have at least 3 elements.")
    end

    _check_connectivity(data, cap; context="capacitor $id")
end


function create_capacitor(; kwargs...)
    cap = Dict{String,Any}()

    add_kwarg!(cap, kwargs, :status, 1)
    add_kwarg!(cap, kwargs, :configuration, "wye")
    add_kwarg!(cap, kwargs, :connections, collect(1:4))
    add_kwarg!(cap, kwargs, :qd_ref, fill(0.0, 3))

    _add_unused_kwargs!(cap, kwargs)

    return cap
end


# Shunt

DTYPES[:shunt] = Dict(
    :id => Any,
    :status => Int,
    :bus => Any,
    :connections => Vector,
    :g_sh => Array{<:Real, 2},
    :b_sh => Array{<:Real, 2},
)

REQUIRED_FIELDS[:shunt] = keys(DTYPES[:shunt])


CHECKS[:shunt] = function check_shunt(data, shunt)
    _check_connectivity(data, shunt; context="shunt $id")

end


function create_shunt(; kwargs...)
    shunt = Dict{String,Any}()

    N = length(kwargs[:connections])

    add_kwarg!(shunt, kwargs, :status, 1)
    add_kwarg!(shunt, kwargs, :g_sh, fill(0.0, N, N))
    add_kwarg!(shunt, kwargs, :b_sh, fill(0.0, N, N))

    _add_unused_kwargs!(shunt, kwargs)

    return shunt
end


# voltage source

DTYPES[:voltage_source] = Dict(
    :id => Any,
    :status => Int,
    :bus => Any,
    :connections => Vector,
    :vm =>Array{<:Real},
    :va =>Array{<:Real},
    :pg_max =>Array{<:Real},
    :pg_min =>Array{<:Real},
    :qg_max =>Array{<:Real},
    :qg_min =>Array{<:Real},
)

REQUIRED_FIELDS[:voltage_source] = [:id, :status, :bus, :connections, :vm, :va]

CHECKS[:voltage_source] = function check_voltage_source(data, vs)
    id = vs["id"]
    _check_connectivity(data, vs; context="voltage source $id")
    N = length(vs["connections"])
    _check_has_size(vs, ["vm", "va", "pg_max", "pg_min", "qg_max", "qg_min"], N, context="voltage source $id")

end


function create_voltage_source(; kwargs...)
    vs = Dict{String,Any}()

    add_kwarg!(vs, kwargs, :status, 1)
    add_kwarg!(vs, kwargs, :connections, collect(1:3))

    _add_unused_kwargs!(vs, kwargs)

    return vs
end


# create add_comp! methods
for comp in keys(DTYPES)
    eval(Meta.parse("add_$(comp)!(data_model; kwargs...) = add!(data_model, \"$comp\", create_$comp(; kwargs...))"))
end