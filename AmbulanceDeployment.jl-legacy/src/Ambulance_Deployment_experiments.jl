#=
Author : Guy Farmer
generates a distribution of ambulances for various ambulance counts and stores to a jld file
=#
using AmbulanceDeployment
#using DataFrames, Winston, JLD, CSV, Gurobi, JuMP, GLPK

function generate_deployment()
    hourly_calls = CSV.File(PROJECT_ROOT * "/test/austin-data/Full_WeekdayCalls.csv") |> DataFrame
    # weekend_hourly_calls = CSV.File("data/processed/2-weekend_calls.csv") |> DataFrame
    adjacent_nbhd = CSV.File(PROJECT_ROOT * "/test/austin-data/adjacent_nbhd.csv") |> DataFrame
    coverage = CSV.read(PROJECT_ROOT * "/test/austin-data/coverage_real.csv", DataFrame, header=false)
    coverage = convert(Array{Bool, 2}, coverage[:, :])
    incidents = CSV.File(PROJECT_ROOT * "/test/austin-data/austin_incidents.csv") |> DataFrame


    regions = Int[parse(Int,string(x)) for x in names(hourly_calls[:,6:ncol(hourly_calls)])]
    locations = collect(1:size(coverage,2))
    adjacent = convert(Array, adjacent_nbhd[:,2:ncol(adjacent_nbhd)])[regions,regions] .> 0.5
    demand = convert(Array,hourly_calls[:,6:end]);


    incidents = incidents[.~ismissing.(incidents[!,:stn1_min]), :] # drop 44 calls that were "unreachable" (because all stations are reachable from each other)
    incidents[!,:interarrival_seconds] = [0; incidents[!,:arrival_seconds][2:end] - incidents[!,:arrival_seconds][1:end-1]]
    incidents[!,:isweekday] .= true
    incidents[!,:isweekday][incidents[!,:dow] .== "Sun"] .= false
    incidents[!,:isweekday][incidents[!,:dow] .== "Sat"] .= false;
    incidents = incidents[incidents[!,:isweekday],:]

    regions2index = Dict{Int,Int}(regions[i]=>i for i in 1:length(regions))

#= previously there was an error that didnt account for all the regions because it
it only included regions for incidents. the regions without incidents are changed
to 0=#
    for x in incidents[!,:neighborhood]
        if(!haskey(regions2index,x))
            regions2index[x] = 0
        end
    end
    incidents[!,:neighborhood] = [regions2index[x] for x in incidents[!,:neighborhood]];

    calls = incidents[:,[[:hour,:dow,:month,:year,:neighborhood,:interarrival_seconds];
    Symbol[Symbol("stn$(i)_min") for i in locations]]]

    DataFrames.first(calls, 6)

# We focus on emergency calls during the "peak period" (8AM - 8PM),
# with the emergency calls from the first 3 month as our training set,
# and the subsequent emergency calls from the remaining months as our test set
    peak_period = (hourly_calls[!,:hour] .>= 8) .* (hourly_calls[!,:hour] .<= 20)
    indices = 1:DataFrames.nrow(hourly_calls);
    train_filter = (hourly_calls[!,:year] .== 2019) .* (hourly_calls[!,:month] .<= 3)
    test_filter  = .~train_filter;
    train_indices = indices[train_filter]
    test_indices = indices[test_filter];

# Same as for the hourly calls; but this is for individual emergency calls
    inc_peak_period = (calls[!,:hour] .>= 8) .* (calls[!,:hour] .<= 20)
    inc_indices = 1:DataFrames.nrow(calls);

    inc_train_filter = (calls[!,:year] .== 2019) .* (calls[!,:month] .<= 3)
    inc_test_filter  = .~inc_train_filter

    inc_train_indices = inc_indices[inc_train_filter]
    inc_test_indices = inc_indices[inc_test_filter];

# we distinguish between peak and offpeak hours
    train_peak = indices[peak_period .* train_filter]
    train_offpeak = indices[.~peak_period .* train_filter]

    test_peak = indices[peak_period .* test_filter]
    test_offpeak = indices[.~peak_period .* test_filter]

    p = DeploymentProblem(30, length(locations), length(regions), demand, train_indices,
          test_indices, coverage[regions,:], Array{Bool,2}(adjacent));

    test_inc_peak = inc_peak_period .* inc_test_filter
    test_inc_offpeak = .~inc_peak_period .* inc_test_filter;



## make sure to include @time begin

scenarios = Dict{Symbol, Dict{Int, Vector{Vector{Int}}}}()
generated_deployment = Dict{Symbol, Dict{Int, Vector{Vector{Int}}}}()
upperbounds = Dict{Symbol, Dict{Int, Vector{Float64}}}()
lowerbounds = Dict{Symbol, Dict{Int, Vector{Float64}}}()
upptiming = Dict{Symbol, Dict{Int, Vector{Float64}}}()
lowtiming = Dict{Symbol, Dict{Int, Vector{Float64}}}()
amb_deployment = Dict{Symbol, Dict{Int, Vector{Int}}}()
for(deployment_model, name) in ((dp -> RobustDeployment(dp, α=0.1), :Robust01),
                                  (dp -> RobustDeployment(dp, α=0.05), :Robust005),
                                  (dp -> RobustDeployment(dp, α=0.01), :Robust001),
                                  (dp -> RobustDeployment(dp, α=0.001), :Robust0001),
                                  (dp -> RobustDeployment(dp, α=0.0001), :Robust00001))
    println("$name: ")
    amb_deployment[name] = Dict{Int, Vector{Int}}()
    scenarios[name] = Dict{Int, Vector{Vector{Int}}}()
    generated_deployment[name] = Dict{Int, Vector{Vector{Int}}}()
    upperbounds[name] = Dict{Int, Vector{Float64}}()
    lowerbounds[name] = Dict{Int, Vector{Float64}}()
    upptiming[name] = Dict{Int, Vector{Float64}}()
    lowtiming[name] = Dict{Int, Vector{Float64}}()
    for namb in 30:5:50
        println("$namb ")
        p.nambulances = namb
        model = deployment_model(p)
        set_optimizer(model.m, Gurobi.Optimizer)
        # solve(model, p)
        @time AmbulanceDeployment.optimize!(model, p)
        #print("($(toq())) ")
        amb_deployment[name][namb] = deployment(model)

        # for tracking purposes
        scenarios[name][namb] = model.scenarios
        generated_deployment[name][namb] = model.deployment
        upperbounds[name][namb] = model.upperbounds
        lowerbounds[name][namb] = model.lowerbounds
        upptiming[name][namb] = model.upptiming
        lowtiming[name][namb] = model.lowtiming
    end
    println
end


<<<<<<< Updated upstream
    # for (next_deployment_model, name) in ((next_dp -> StochasticDeployment(next_dp, nperiods=500), :Stochastic),
    #                              (next_dp -> MEXCLPDeployment(next_dp, 0.654), :MEXCLP),
    #                              (next_dp -> MALPDeployment(next_dp, 0.654), :MALP))
    # println("$name: ")
    # amb_deployment[name] = Dict{Int, Vector{Int}}()
    #     for namb in 25:5:50
    #         println("$namb ")
    #         p.nambulances = namb
    #         next_model = next_deployment_model(p)
    #         set_optimizer(next_model.m, Gurobi.Optimizer)
    #         @time AmbulanceDeployment.optimize!(next_model, p)
    #         amb_deployment[name][namb] = deployment(next_model)
    #     end
    #     println()
    # end
    solver_stats = Dict{String, Any}()
    push!(solver_stats, "amb_deployment" => amb_deployment)
    push!(solver_stats, "scenarios" => scenarios)
    push!(solver_stats, "generated_deployment" => generated_deployment)
    push!(solver_stats, "upperbounds" => upperbounds)
    push!(solver_stats, "lowerbounds" => lowerbounds)
    push!(solver_stats, "upptiming" => upptiming)
    push!(solver_stats, "lowtiming" => lowtiming)
    json_string = JSON.json(solver_stats)

    open("src/outputs/solver_stats.json","w") do f
        write(f, json_string)
    end

end
=======
         for (next_deployment_model, name) in ((next_dp -> StochasticDeployment(next_dp, nperiods=500), :Stochastic),
                                         (next_dp -> MEXCLPDeployment(next_dp, 0.654), :MEXCLP),
                                         (next_dp -> MALPDeployment(next_dp, 0.654), :MALP))
            println("$name: ")
            amb_deployment[name] = Dict{Int, Vector{Int}}()
            for namb in 25:5:50
                println("$namb ")
                p.nambulances = namb
                next_model = next_deployment_model(p)
                set_optimizer(next_model.m, Gurobi.Optimizer)
                @time AmbulanceDeployment.optimize!(next_model, p)
                amb_deployment[name][namb] = deployment(next_model)
            end
            println()
        end
solver_stats = Dict{String, Any}()
push!(solver_stats, "amb_deployment" => amb_deployment)
push!(solver_stats, "scenarios" => scenarios)
push!(solver_stats, "generated_deployment" => generated_deployment)
push!(solver_stats, "upperbounds" => upperbounds)
push!(solver_stats, "lowerbounds" => lowerbounds)
push!(solver_stats, "upptiming" => upptiming)
push!(solver_stats, "lowtiming" => lowtiming)
json_string = JSON.json(solver_stats)

open("src/outputs/solver_stats.json","w") do f
                   write(f, json_string)
               end
>>>>>>> Stashed changes
