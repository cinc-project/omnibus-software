#!/bin/bash

# shellcheck disable=SC1090

echo "--- Setting Omnibus build environment variables"

export PATH="/opt/omnibus-toolchain/bin:${PATH}"
echo "PATH=${PATH}"

if [[ -f "/opt/omnibus-toolchain/embedded/ssl/certs/cacert.pem" ]]; then
  export SSL_CERT_FILE="/opt/omnibus-toolchain/embedded/ssl/certs/cacert.pem"
  echo "SSL_CERT_FILE=${SSL_CERT_FILE}"
fi

if [[ $SOFTWARE == "libxslt" ]]; then
  echo "--- Installing libxml2-dev for libxslt"
  apt-get install -y libxml2-dev
fi

###################################################################
# Query tool versions
###################################################################
echo ""
echo ""
echo "========================================"
echo "= Tool Versions"
echo "========================================"
echo ""
echo "$(head -1 /opt/omnibus-toolchain/version-manifest.txt)"
echo ""
echo "Bash.........$(bash --version | head -1)"
echo "Bundler......$(bundle --version | head -1)"
echo "GCC..........$(gcc --version | head -1)"
echo "Git..........$(git --version | head -1)"
echo "Make.........$(make --version | head -1)"
echo "Ruby.........$(ruby --version | head -1)"
echo "RubyGems.....$(gem --version | head -1)"
echo ""
echo "========================================"

rm -f Gemfile.lock

if [[ $CI == true ]]; then
  bundle config set --local path ${CI_PROJECT_DIR}/bundle/vendor
  bundle config set --local without development
fi

echo "--- Running bundle install"

git config --global --add safe.directory /omnibus-software
bundle install

if [[ $SKIP_HEALTH_CHECK == true ]] ; then
  echo "--- Skipping health checks"
fi

if [[ $CI == true ]]; then
  echo "--- Building"
  bundle exec omnibus build test -l ${OMNIBUS_LOG_LEVEL:-info} --override append_timestamp:false
  exit $?
fi
