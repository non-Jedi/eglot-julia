# Usage:
#   julia --project=path/to/eglot-jl path/to/eglot-jl/eglot-jl.jl [SOURCE_PATH] [DEPOT_PATH]

# For convenience, Pkg isn't included in eglot-jl
# Project.toml. Importing Pkg here relies on the standard library
# being available on LOAD_PATH
import Pkg

# By default, look for environments stored alongside eglot-jl's sources
const ENV_PATH = [@__DIR__]

# ... but users can provide a writable location to store their environments
if "EGLOT_JL_ENVDIR" ∈ keys(ENV)
    mkpath(ENV["EGLOT_JL_ENVDIR"])
    pushfirst!(ENV_PATH, ENV["EGLOT_JL_ENVDIR"])
end

# Look for all already instantiated environments with
# compatible Julia versions
envs = Iterators.flatten(readdir(path, join=true) for path in ENV_PATH)
envs = map(envs) do dir
    ispath(joinpath(dir, "Project.toml")) || return nothing

    m = match(r"env-(.+)", dir)
    isnothing(m) && return nothing

    v = VersionNumber(m[1])
    v > VERSION && return nothing

    return (v, dir)
end
filter!(!isnothing, envs) |> sort!
foreach(envs) do (version, dir)
    @debug "Found compatible environment" version dir
end

# Our best candidate is the one with the latest compatible version
(base_ver, base_dir) = last(envs)

if base_ver == VERSION
    # A suitable environment has been found: simply instantiate it
    Pkg.activate(base_dir)
    Pkg.instantiate()
else
    # No suitable environment can be found: create one
    env_dir = joinpath(first(ENV_PATH), "env-$(VERSION)")

    @info "Creating new version-specific environment" env_dir base_dir
    mkpath(env_dir)
    cp(joinpath(base_dir, "Project.toml"),
       joinpath(env_dir,  "Project.toml"))

    if (ispath(joinpath(base_dir, "Manifest.toml")))
        cp(joinpath(base_dir, "Manifest.toml"),
           joinpath(env_dir,  "Manifest.toml"))
    end

    Pkg.activate(env_dir)
    Pkg.resolve()
end

# Get the source path. In order of increasing priority:
# - default value:  pwd()
# - command-line:   ARGS[1]
src_path = length(ARGS) >= 1 ? ARGS[1] : pwd()

# Get the depot path. In order of increasing priority:
# - default value:  ""
# - environment:    ENV["JULIA_DEPOT_PATH"]
# - command-line:   ARGS[2]
depot_path = get(ENV, "JULIA_DEPOT_PATH", "")
if length(ARGS) >= 2 && ARGS[2] != ""
    depot_path = ARGS[2]
end

# Get the project environment from the source path
project_path = something(Base.current_project(src_path), Base.load_path_expand(LOAD_PATH[2])) |> dirname

# Make sure that we only load packages from this environment specifically.
empty!(LOAD_PATH)
push!(LOAD_PATH, "@")

using LanguageServer, SymbolServer

@info "Running language server" env=Base.load_path()[1] src_path project_path depot_path
server = LanguageServerInstance(stdin, stdout, project_path, depot_path)
run(server)
