// Command yup-git is the CLI wrapper around github.com/gloo-foo/cmd-git.
package main

import (
	clix "github.com/gloo-foo/cli"
	command "github.com/gloo-foo/cmd-git"
)

// version is the build version. It defaults to "dev" for local builds and is
// overridden at release time via the linker: -ldflags "-X main.version=<v>".
var version = "dev"

const name = "git"

// Error is the package's sentinel error type, so every emitted error path is
// comparable with errors.Is.
type Error string

func (e Error) Error() string { return string(e) }

// ErrNoArgs is emitted when no git subcommand is given; git itself treats a bare
// invocation as a usage error, so the wrapper rejects it up front.
const ErrNoArgs Error = "no git subcommand given"

// synopsis is the multi-line --help usage block; urfave/cli indents it three
// spaces, so the lines stay flush-left.
const synopsis = `git COMMAND [ARG...]

Execute git commands, piping standard input to git and
git's standard output onward.`

// spec declares the git wrapper: a stdin filter whose operands are git's own
// subcommand and arguments, passed through verbatim.
var spec = clix.Spec{
	Name:     name,
	Summary:  "git command wrapper for yupsh",
	Synopsis: synopsis,
	Build:    build,
}

// build maps the invocation to git's pipeline: standard input feeds git, whose
// subcommand and arguments are the operands. A bare invocation is a usage error.
func build(inv clix.Invocation) (clix.Source, clix.Command, error) {
	operands := inv.Args.Args().Slice()
	if len(operands) == 0 {
		return nil, nil, ErrNoArgs
	}
	args := make([]command.GitArg, len(operands))
	for i, o := range operands {
		args[i] = command.GitArg(o)
	}
	return clix.Stdin(inv.Stdin), command.Git(args...), nil
}

// runMain is an indirection seam so main's wiring is testable without spawning
// the process; a test swaps it and restores it.
var runMain = clix.Main

func main() { runMain(spec, version) }
