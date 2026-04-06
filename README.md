# Omnibus Software

[![Pipeline Status](https://gitlab.com/cinc-project/upstream/omnibus-software/badges/stable/cinc/pipeline.svg)](https://gitlab.com/cinc-project/upstream/omnibus-software/-/pipelines)

This repository contains shared software descriptions, for use by any [Omnibus](https://github.com/chef/omnibus) project that needs them. It is maintained by the [CINC Project](https://cinc.sh) as a community fork.

For more information on writing your own software definitions, please see [the Omnibus README](https://github.com/chef/omnibus#sharing-software-definitions).

## Versioning

This repository is versioned and tagged using the `YY.MM.BUILD` to allow folks to be able to access the state of the software definition at a specific point in time. We do however encourage folks to pull in the latest whenever possible.

## Project Configuration Overrides

Omnibus projects can override software configurations by providing override values in their project configuration. The following software projects defined in this repo have additional options.

### Ruby OpenSSL Configuration

When using Ruby with OpenSSL >= 3.0 in your omnibus project, you can override the OpenSSL gem version used:

```ruby
# In your omnibus project configuration
override :ruby, version: "3.1.3", openssl_gem: "3.2.0"
```

This is particularly useful when:

- Using Ruby < 3.1 with OpenSSL >= 3.0
- FIPS mode is enabled
- You need a specific OpenSSL gem version for compatibility

_Warning_: You need to also be sure to install the same version via your `Gemfile`, as this option just grabs a copy of the `openssl.rb` for initial native gem building. The installed gem for you project needs to match or else there is a chance of breakage of OpenSSL functionality.

### OpenSSL Version Configuration

You can override the OpenSSL version used in your project and specify an alternative to the 3.0.9 FIPS version that is the default:

```ruby
# In your omnibus project configuration  
override :openssl, version: "3.4.1", fips_version: "3.1.2"
```

The Ruby software definition will automatically detect when OpenSSL >= 3.0 is being used and configure the appropriate OpenSSL gem installation for compatibility. Specifying the `:fips_version` will indicate the OpenSSL library version from which the FIPS module should be used. Currently, only `3.0.9` and `3.1.2` in the software definition are validated. See [CVEs and the FIPS Provider](https://openssl-library.org/news/fips-cve/) for a list of 3.0.0 FIPS releases.

## Contributing

For information on contributing to this project, please open a merge request on [GitLab](https://gitlab.com/cinc-project/upstream/omnibus-software).

### Run Linux Tests in Docker

Run the tests in the Ruby image of your choice:

```
docker run -it --rm -v $PWD:/src -w /src ruby:3.3 bash -c "bundle install && bundle exec rake"
```

### Testing via Docker

#### Interactive Testing

If you want to enter an interactive shell in a dockerized omnibus build environment on Ubuntu 18.04 you can run the following command.

```
docker-compose run --rm -e SOFTWARE=<SOFTWARE> -e VERSION=<VERSION> builder

# Example
docker-compose run --rm -e SOFTWARE=go -e VERSION=1.17.6 builder
```

Now you should be in a shell in the container ready to explore, modify or build. The omnibus-software repository will be mounted inside the container which makes it easy to edit code with your editor and test it in the container.

You can start the build by running the following command in your shell.

```
bundle exec omnibus build test
```

Omnibus git caching is enabled for the build so you can rerun the build command and it will use the cache for any software that was already successfully built. This can save a lot of time when troubleshooting software that has dependencies on other software that builds fine.

The following command will clean the omnibus project and purge the packages and caches.

```
bundle exec omnibus clean test --purge
```

The container will automatically be destroyed when you exit it without requiring any further cleanup.

#### Non-Interactive Testing

If you only want to run a build without an interactive shell you can set the `CI` environment variable as you see in the following command.

```
docker-compose run --rm -e SOFTWARE=<SOFTWARE> -e VERSION=<VERSION> -e CI=true builder
```

The container will automatically be destroyed when you exit it without requiring any further cleanup.

## License & Copyright

- Copyright:: Copyright (c) 2012-2021 Chef Software, Inc.
- Copyright:: Copyright (c) 2019-2026 CINC Project
- License:: Apache License, Version 2.0

```text
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License..
```
