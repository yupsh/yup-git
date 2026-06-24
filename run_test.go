package main

import (
	"bytes"
	"io"
	"strings"
	"testing"

	"github.com/spf13/afero"
)

func TestRun(t *testing.T) {
	cases := []struct {
		name       string
		version    string
		args       []string
		stdin      string
		wantOutSub string
		wantCode   int
		wantErrSub string
	}{
		{
			name:       "version flag reports injected version",
			version:    "1.2.3",
			args:       []string{"git", "--version"},
			wantOutSub: "git version 1.2.3\n",
		},
		{
			name:       "subcommand passthrough reports git's own version",
			args:       []string{"git", "version"},
			wantOutSub: "git version",
		},
		{
			name:       "bogus subcommand errors",
			args:       []string{"git", "not-a-real-subcommand"},
			wantCode:   1,
			wantErrSub: "git:",
		},
		{
			name:       "no args sentinel",
			args:       []string{"git"},
			wantCode:   1,
			wantErrSub: "git:",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var out, errOut bytes.Buffer
			code := run(tc.version, tc.args, strings.NewReader(tc.stdin), &out, &errOut, afero.NewMemMapFs())

			if code != tc.wantCode {
				t.Fatalf("exit code = %d, want %d (stderr=%q)", code, tc.wantCode, errOut.String())
			}
			if tc.wantOutSub != "" && !strings.Contains(out.String(), tc.wantOutSub) {
				t.Fatalf("stdout = %q, want substring %q", out.String(), tc.wantOutSub)
			}
			if tc.wantErrSub != "" && !strings.Contains(errOut.String(), tc.wantErrSub) {
				t.Fatalf("stderr = %q, want substring %q", errOut.String(), tc.wantErrSub)
			}
		})
	}
}

func Test_main(t *testing.T) {
	origExit, origRun := osExit, runCLI
	t.Cleanup(func() { osExit, runCLI = origExit, origRun })

	gotCode := -1
	osExit = func(code int) { gotCode = code }
	runCLI = func(string, []string, io.Reader, io.Writer, io.Writer, afero.Fs) int { return 7 }

	main()

	if gotCode != 7 {
		t.Fatalf("main propagated exit code %d, want 7", gotCode)
	}
}
