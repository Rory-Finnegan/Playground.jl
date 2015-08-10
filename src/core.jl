using ArgParse
using Logging

include("utils.jl")

JULIA_GIT_ADDRESS = "https://github.com/JuliaLang/julia.git"
ACTIVATED_PROMPT = "playground> "


function manage_playground()
    parse_settings = ArgParseSettings()

    @add_arg_table parse_settings begin
        "directory"
            help = "The path for the virtualenv directory."
            required = true
        "create"
            action = :command
            help = "builds th playground"
        "activate"
            action = :command
            help = "activates the playground"
    end

    @add_arg_table parse_settings["create"] begin
        "--julia", "-j"
            help = "The version of julia to use.  You can pass in either the julia version number which will build a fresh version of julia in the virtualenv or you can pass a prebuilt system path to use.  By default the user/system level version is used."
            action = :store_arg
            default = ""
        "--clear", "-c"
            help = "Clear out the virtualenv and rebuild it from scratch."
            action = :store_true
    end

    args = parse_args(parse_settings)

    cmd = args["%COMMAND%"]
    if cmd == "create"
        create(args["directory"], args[cmd]["julia"], args[cmd]["clear"])
    elseif cmd == "activate"
        activate(args["directory"])
    end
end


function create(directory, julia, clear)
    if julia == "" || ispath(julia) ||
        '.' in julia || ismatch(r"\b([a-f0-9]{40})\b", julia)

        root_path = abspath(directory)
        bin_path = joinpath(root_path, "bin")
        log_path = joinpath(root_path, "log")
        pkg_path = joinpath(root_path, "packages")
        julia_path = joinpath(bin_path, "julia")
        julia_src_path = joinpath(root_path, "julia_src")
        gitlog = joinpath(log_path, "git.log")

        mkpath(root_path)
        mkpath(bin_path)
        mkpath(log_path)
        mkpath(pkg_path)

        Logging.configure(level=DEBUG, filename=joinpath(log_path, "playground.log"))
        Logging.info("Playground folders created")

        if julia != ""
            if ispath(julia)
                Logging.info("Linking supplied julia binary to bin/julia")
                mklink(julia, julia_path)
            else
                Logging.info("Cloning the julia repository into the playground")
                run(`git clone $(JULIA_GIT_ADDRESS) $(julia_src_path)` |> gitlog)

                # Handle the cd into and out of src directory cause cd() in base
                # seems to be broken.
                cwd = pwd()
                cd(julia_src_path)
                build_julia(julia, root_path, log_path)
                cd(cwd)
            end
        end
    else
        error("Invalid julia input please ensure you are " *
            "passing either a valid julia path, version or SHA1")
    end
end


function activate(directory)
    root_path = abspath(directory)
    log_path = joinpath(root_path, "log")
    bin_path = joinpath(root_path, "bin")
    pkg_path = joinpath(root_path, "packages")

    Logging.configure(level=DEBUG, filename=joinpath(log_path, "playground.log"))

    Logging.info("Setting PATH variable to using to look in playground bin directory first")
    ENV["PATH"] = "$(bin_path):" * ENV["PATH"]
    Logging.info("Setting the JULIA_PKGDIR variable to using the playground packages directory")
    ENV["JULIA_PKGDIR"] = pkg_path

    Logging.info("Executing a playground shell")
    @windows? run_windows_shell() : run_nix_shell()
end


function run_windows_shell()
    run(`cmd /K prompt $(ACTIVATED_PROMPT)`)
end


function run_nix_shell()
    ENV["PS1"] = ACTIVATED_PROMPT
    run(`sh -i`)
end


function build_julia(target, root_path, log_path)
    Logging.info("Building julia ( $(target) )...")
    gitlog = joinpath(log_path, "git.log")
    buildlog = joinpath(log_path, "build.log")

    run(`git checkout $(target)` >> gitlog)
    Logging.info("checking out $(target)")

    # Write the different prefix to the Make.user file before
    # building and installing.
    Logging.info("setting prefix in Make.user")
    fstrm = open("Make.user","w")
    write(fstrm, "prefix=$(root_path)")

    Logging.info("Building julia")
    # Build and install.
    # TODO: log the build output properly in root_dir/log
    run(`make` |> buildlog)
    run(`make install` >> buildlog)
    println("Julia has been built and installed.")
end

