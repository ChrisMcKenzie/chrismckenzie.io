---
title: Deploying with Go
tags:  
  - Golang 
  - Deployment 
  - Development 
  - Makefile 
  - Wercker
aliases:
  - '/blog/2015/02/23/deploying-with-golang/'
comments: true
date: '2015-02-23'
image: /assets/golang.jpg
---

Recently I have been building a lot of go applications, and I think I have 
come up with a good pattern for building an app that is ready for deployment
to either a server or to users. This includes build/run for development, testing,
dependency management, and packaging. While this process is still being actively developed I believe it is at a 
state in which to share.

<!-- more -->


## The Structure
I keep a very simple structure for my projects and it is as follows.

```
  |- my-project
    |- bin/     # place to store binaries (in .gitignore)
    |- dist/    # place to store packaged apps (in .gitignore)
    |- pkg/     # for sub-packages
    |- _vendor/ # our custom GOPATH (optional .gitignore)
    |- Makefile
    |- main.go
    |- wercker.yml
```


## The Makefile
The meat and potatoes of this workflow starts with the `Makefile` for those 
who don't know [`make`](http://en.wikipedia.org/wiki/Make_%28software%29) 
is a build system. Make allows us to download dependencies, keep version, 
as well build and package.

```make
.PHONY: version all run dist clean
APP_NAME := my-project
SHA := $(shell git rev-parse --short HEAD)
BRANCH := $(subst /,-,$(shell git rev-parse --abbrev-ref HEAD))
VER := 0.0.1
DIR=.

ifdef WERCKER_OUTPUT_DIR 
  DIR = $(WERCKER_OUTPUT_DIR)
endif

ifdef APP_SUFFIX
  VERSION = $(VER)-$(subst /,-,$(APP_SUFFIX))
else 
  VERSION = $(VER)-$(BRANCH)
endif

BUILD := $(SHA)-$(BRANCH)

# Go setup
GO=go
TEST=go test
GOPATH := ${PWD}/_vendor:${GOPATH}
export GOPATH

DEPENDENCIES := github.com/gin-gonic/gin \
                github.com/dancannon/gorethink

# Sources and Targets
EXECUTABLES :=bin/$(APP_NAME)
# Build Binaries setting main.version and main.build vars
LDFLAGS :=-ldflags "-X main.version $(VERSION) -X main.build $(BUILD)"
# Package target
PACKAGE :=$(DIR)/dist/$(APP_NAME)-$(VERSION).tar.gz

# Custom go path for project
VENDOR_DIR :=_vendor/src
DEPENDENCIES_DIR := $(addprefix $(VENDOR_DIR),$(DEPENDENCIES))

.DEFAULT: all

all: | $(EXECUTABLES)

# print the version
version:
  @echo $(VERSION)
# print the name of the app
name:
  @echo $(APP_NAME)

# print the package path
package:
  @echo $(PACKAGE)

# We have to set GOPATH to just the _vendor
# directory to ensure that `go get` doesn't
# update packages in our primary GOPATH instead.
# This will happen if you already have the package
# installed in GOPATH since `go get` will use
# that existing location as the destination.
$(DEPENDENCIES_DIR):
  @echo Downloading $(@:$(VENDOR_DIR)%=%)...
  @GOPATH=${PWD}/_vendor go get $(@:$(VENDOR_DIR)%=%)

# This defines the req's for each binary
# if you only have one then these can be placed under
# $(EXECUTABLES): Target
# you must define the main file for each binary that will
# be placed in bin.
# For Example:
# -----------
# binary #1
# bin/$(APP_NAME): main.go pkg/* $(DEPENDENCIES_DIR)
# binary #2
# bin/my_other_bin: other.go pkg/* $(DEPENDENCIES_DIR)
bin/$(APP_NAME): main.go $(DEPENDENCIES_DIR) 

$(EXECUTABLES): 
  $(GO) build $(LDFLAGS) -o $@ $<

run: bin/$(APP_NAME)
  bin/$(APP_NAME)

test: 
  $(TEST) -r -cover

clean:
  @echo Cleaning Workspace...
  rm -dRf _vendor
  rm -dRf bin
  rm -dRf dist

$(PACKAGE): all
  @echo Packaging Binaries...
  @mkdir -p tmp/$(APP_NAME)/bin
  @cp -R bin/ tmp/$(APP_NAME)/
  @mkdir -p $(DIR)/dist/
  tar -cf $@ -C tmp $(APP_NAME);
  @rm -rf tmp

dist: $(PACKAGE)
``` 

This gives us a small list of important commands:

-  `make` will build all of the targets defined in EXECUTABLES
-  `make test` will run go test or whatever you set TEST to 
-  `make clean` will remove dirs `bin`, `_vendor`, and `dist`
-  `make dist` will package your app into a tarball in the `dist` dir.

You may have also noticed a few things pertaining to versioning these 
are some cool tricks to make versioning awesome and easy when releasing 
your app into the wild. 

The first is the `VERSION` variable, it is composed of two parts the 
[semver](http://semver.org/), a tag (`beta`, `rc`, etc) or the branch name.
The second part is the `BUILD` variable, it is composed of two parts the 
commit sha, and the branch it was built from. 

This all comes together in the `LDFLAGS` variable which will set two 
corresponding variables in the `main` package of your code which you 
could then use to populate a cli message among other things. The power of
this is that we can keep our versioning in one place and it will affect 
all other parts of our project. You will see more of this in the next part.

## The wercker.yml
For those who do not know what [wercker](http://wercker.com/) is, I urge you 
to check it out, it's currently my favorite CI/CD tool and it's free while they 
are in beta. I use wercker as my platform for testing my code and more 
importantly building/releasing my code. In order to use wercker you must first 
setup your repo in wercker, then you must add a `wercker.yml` file to your repo. 
Wercker gives us two flows, a Build Flow and a Deploy Flow and they do exactly 
that.

My wercker configuration takes advantage of a lot of werckers features namely
the Custom deploy targets and Pipeline variables. this allows me to create deploy
targets for both _final_ releases and _release candidates_. My "deployments" 
are in the form of [Github Releases](https://github.com/blog/1547-release-your-software)
and recieve a tag of the version, and the packaged binaries.

```yaml
box: wercker/golang@1.2.3

deploy:
    steps:
        # Sets the go workspace and places your package
        # at the right place in the workspace tree
        - setup-go-workspace
        - script: 
            name: Build App
            code: make dist
        - script:
            name: Make Exports
            code: | 
                export APP_VERSION=$(make version)
                export PACKAGE_PATH=$(make package)
        - github-create-release:
            token: $GITHUB_TOKEN
            tag: v$APP_VERSION
            prerelease: $PRE_RELEASE
            title: Version $APP_VERSION
        - github-upload-asset:
            token: $GITHUB_TOKEN
            file: $PACKAGE_PATH
            release_id: $WERCKER_GITHUB_CREATE_RELEASE_ID

# Build definition
build:
  # The steps that will be executed on build
  steps:
    # Sets the go workspace and places your package
    # at the right place in the workspace tree
    - setup-go-workspace
    - script:
        name: Unit Test
        code: |
            make test

```

This file will instruct wercker to first run tests on your project and then
once completed you may run a "deploy" on your test that will package up your
app and then ship the tarball off to github release with git tags on the 
given commit. There are however a few steps needed to make this work, you 
must first create a deploy target in wercker by going to your project and
clicking `settings` -> `deploy targets` and adding a new "Custom Deploy"
target you may then choose a name such as "release" and select whether you 
wish to auto-deploy a specific branch. Next you must add two pipeline variables
an `APP_SUFFIX` which will contain the identifier for this release (eq: `beta`),
and a `PRE_RELEASE` variable which can be `true` or `false` and will flag the 
release in github as a pre-release, and thats it you should be able to fire off 
a build and release it directly to your repos github releases.

## Final Thoughts

With the given `Makefile`, `wercker.yml`, and filesystem structure I have been 
able to quickly and easily bootstrap applications with CI/CD as well as a 
nice way to manage dependencies that works everywhere. I hope this is a useful
resource and I will continue to update this process with new additions as I
find them.

## Links 
 - [Wercker](http://wercker.com)
 - [Demo Project](https://github.com/ChrisMcKenzie/Deploy-With-Golang-Demo)

