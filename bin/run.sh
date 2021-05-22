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
build_dir=/tmp/build
cache_dir=${build_dir}/cache

if [ ! -d "${input_dir}" ]; then
    echo "No such directory: ${input_dir}"
    exit 1
fi

# Create the output directory if it doesn't exist
mkdir -p "${output_dir}"

# Prepare build directory
if [ -d "${build_dir}" ]; then
    rm -rf ${build_dir}
fi

mkdir -p ${build_dir}
mkdir -p ${cache_dir}
cp "${input_dir}"/*.dhall ${build_dir}
cp -R -p "${base_dir}/pre-compiled/.spago" ${build_dir}
cp -R -p "${base_dir}/pre-compiled/output" ${build_dir}
ln -sfn "${base_dir}/pre-compiled/node_modules" ${build_dir}
ln -s "${input_dir}"/src ${build_dir}/src
ln -s "${input_dir}"/test ${build_dir}/test
cp -R "${HOME}"/.cache/dhall ${cache_dir}
cp -R "${HOME}"/.cache/dhall-haskell ${cache_dir}

pushd "${build_dir}" > /dev/null || exit

echo "Build and test ${slug}..."

# Run the tests for the provided implementation file and redirect stdout and
# stderr to capture it. We do our best to minimize the output to emit and
# compiler errors or unit test output as this scrubbed and presented to the
# student. In addition spago will try to write to ~/cache/.spago and will fail
# on a read-only mount and thus we skip the global cache and request to not
# install packages.
export XDG_CACHE_HOME=${cache_dir}
spago_output=$(npx spago --quiet --global-cache skip --no-psa test --no-install 2>&1)
exit_code=$?

popd > /dev/null || exit

# Write the results.json file based on the exit code of the command that was
# just executed that tested the implementation file.
if [ $exit_code -eq 0 ]; then
    jq -n '{version: 1, status: "pass"}' > "${results_file}"
else
    sanitized_spago_output=$(echo "${spago_output}" | sed -E \
      -e '/^Compiling/d' \
      -e '/at.*:[[:digit:]]+:[[:digit:]]+\)?/d')

    jq --null-input --arg output "${sanitized_spago_output}" \
        '{version: 1, status: "fail", output: $output}' > "${results_file}"
fi

echo "Done"
