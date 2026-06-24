package main

import (
	"context"
	"fmt"
	"io"

	command "github.com/gloo-foo/cmd-git"
	gloo "github.com/gloo-foo/framework"
	"github.com/spf13/afero"
	"github.com/urfave/cli/v3"
)

// Error is the package's sentinel error type, making every emitted error path
// comparable with errors.Is.
type Error string

func (e Error) Error() string { return string(e) }

// ErrNoArgs is emitted when no git subcommand is given; git itself treats a
// bare invocation as a usage error, so the wrapper rejects it up front.
const ErrNoArgs Error = "no git subcommand given"

// usageText is the command's multi-line usage synopsis, shown in --help.
// cli/v3 indents the whole block by 3 spaces, so these lines are flush-left to
// stay aligned in the rendered output.
const usageText = `git COMMAND [ARG...]

Execute git commands, piping standard input to git and
git's standard output onward.`

// init replaces urfave/cli's default --version/-v flag with a --version-only
// flag, freeing the single-letter -v for command flags (e.g. git status -v)
// while still exposing the injected build version.
func init() {
	cli.VersionFlag = &cli.BoolFlag{Name: "version", Usage: "print version information and exit"}
}

// run builds and executes the git CLI against the injected version, I/O, and
// filesystem, returning the process exit code.
func run(version string, args []string, stdin io.Reader, stdout, stderr io.Writer, _ afero.Fs) int {
	cmd := newApp(version, stdin, stdout)
	cmd.Writer = stdout
	cmd.ErrWriter = stderr
	if err := cmd.Run(context.Background(), args); err != nil {
		_, _ = fmt.Fprintf(stderr, "git: %v\n", err)
		return 1
	}
	return 0
}

func newApp(version string, stdin io.Reader, stdout io.Writer) *cli.Command {
	return &cli.Command{
		Name:            "git",
		Version:         version,
		Usage:           "git command wrapper for yupsh",
		UsageText:       usageText,
		HideHelpCommand: true,
		// Keep exit handling in run() rather than letting urfave/cli call
		// os.Exit, so the exit code stays testable.
		ExitErrHandler: func(context.Context, *cli.Command, error) {},
		Action:         action(stdin, stdout),
	}
}

func action(stdin io.Reader, stdout io.Writer) cli.ActionFunc {
	return func(_ context.Context, c *cli.Command) error {
		if c.NArg() == 0 {
			return ErrNoArgs
		}
		source := gloo.ByteReaderSource([]io.Reader{stdin})
		_, err := gloo.Run(source, gloo.ByteWriteTo(stdout), command.Git(c.Args().Slice()...))
		return err
	}
}
