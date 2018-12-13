#!/usr/bin/env lsc -cj
#

# Known issue:
#   when executing the `package.ls` directly, there is always error
#   "/usr/bin/env: lsc -cj: No such file or directory", that is because `env`
#   doesn't allow space.
#
#   More details are discussed on StackOverflow:
#     http://stackoverflow.com/questions/3306518/cannot-pass-an-argument-to-python-with-usr-bin-env-python
#
#   The alternative solution is to add `envns` script to /usr/bin directory
#   to solve the _no space_ issue.
#
#   Or, you can simply type `lsc -cj package.ls` to generate `package.json`
#   quickly.
#

# package.json
#
name: \yapps

author:
  name: ['Yagamy']
  email: 'yagamy@gmail.com'

description: "the app framework for nodejs applications on embedded linux system"

version: \0.0.1

repository:
  type: \git
  url: ''

main: \index

engines:
  node: \8.x
  npm: \1.4.x

dependencies:
  async: \^2.6.1
  colors: \^1.3.0
  lodash: \^4.17.10
  mkdirp: \^0.5.1
  moment: \*

devDependencies: {}

optionalDependencies: {}
