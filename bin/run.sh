#!/usr/bin/env bash

# Synopsis:
# Run the test runner on a solution.

# Arguments:
# $1: exercise slug
# $2: absolute path to solution folder
# $3: absolute path to output directory

# Output:
# Writes the test results to a results.json file in the passed-in output directory.
# The test results are formatted according to the specifications at
# https://github.com/exercism/docs/blob/main/building/tooling/test-runners/interface.md

# Example:
# ./bin/run.sh two-fer /absolute/path/to/two-fer/solution/folder/ /absolute/path/to/output/directory/

set -o pipefail
set -u

# If required arguments are missing, print the usage and exit
if [ $# != 3 ]; then
    echo "usage: ./bin/run.sh exercise-slug /absolute/path/to/two-fer/solution/folder/ /absolute/path/to/output/directory/"
    exit 1
fi

base_dir=$(builtin cd "${BASH_SOURCE%/*}/.." || exit; pwd)

slug="$1"
input_dir="${2%/}"
output_dir="${3%/}"
results_file="${output_dir}/results.json"

if [ ! -d "${input_dir}" ]; then
    echo "No such directory: ${input_dir}"
    exit 1
fi

# Create the output directory if it doesn't exist
mkdir -p "${output_dir}"

pushd "${input_dir}" > /dev/null || exit

echo "Build and test ${slug}..."

ln -sfn "${base_dir}/pre-compiled/node_modules" .
ln -sfn "${base_dir}/pre-compiled/.spago" .

# We can't symlink this as spago will write the compiled modules in the
# `ouput/` directory. The timestamps of the `output/` directory must be
# preserved or else PureScript compiler (`purs`) will invalidate the cache and
# force a rebuild defeating pre-compiling altogether (and thus the usage of the
# `cp` `-p` flag).
#
# Note that under Docker `output/` should be mounted in a tmpfs to avoid
# copying between the docker host and client giving a nice speed boost.
cp -R -p "${base_dir}/pre-compiled/output" .

# Run the tests for the provided implementation file and redirect stdout and
# stderr to capture it. We do our best to minimize the output to emit and
# compiler errors or unit test output as this scrubbed and presented to the
# student. In addition spago will try to write to ~/cache/.spago and will fail
# on a read-only mount and thus we skip the global cache and request to not
# install packages.
export XDG_CACHE_HOME=/tmp
spago_output=$(npx spago -V --global-cache skip --no-psa test --no-install 2>&1)
exit_code=$?

popd > /dev/null || exit

# Write the results.json file based on the exit code of the command that was
# just executed that tested the implementation file.
if [ $exit_code -eq 0 ]; then
    jq -n '{version: 1, status: "pass"}' > "${results_file}"
else
    echo "${spago_output}"
    sanitized_spago_output=$(echo "${spago_output}" | sed -E \
      -e '/^Compiling/d' \
      -e '/at.*:[[:digit:]]+:[[:digit:]]+\)?/d')

    jq --null-input --arg output "${sanitized_spago_output}" \
        '{version: 1, status: "fail", output: $output}' > "${results_file}"
fi

echo "Done"
