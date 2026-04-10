#
# Copyright 2016 Chef Software, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# ## libintl-perl
# libintl-perl is a localization library.

name "libintl-perl"

default_version "1.37"

license "GPL-3.0"
license_file "COPYING"

dependency "perl"
dependency "cpanminus"

# version_list: url=https://cpan.metacpan.org/authors/id/G/GU/GUIDO/ filter=libintl-perl-*.tar.gz

version("1.37") { source sha256: "a49b08d56813789e5f03289a3f949459eafe9e40a1a9fc066c42c90009a322cf" }

source url: "https://cpan.metacpan.org/authors/id/G/GU/GUIDO/libintl-perl-#{version}.tar.gz"
internal_source url: "#{ENV["ARTIFACTORY_REPO_URL"]}/#{name}/#{name}-#{version}.tar.gz",
                authorization: "X-JFrog-Art-Api:#{ENV["ARTIFACTORY_TOKEN"]}"

relative_path "libintl-perl-#{version}"

# See https://github.com/theory/sqitch for more

build do
  env = with_standard_compiler_flags(with_embedded_path)

  command "cpanm -v --notest .", env: env
end
