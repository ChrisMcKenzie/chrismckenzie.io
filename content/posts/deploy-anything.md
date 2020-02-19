---
title: "Deploying Anything with Dropship"
tags:
  - deployment
  - golang
  - dropship
comments: true
date: '2015-11-17'
---

So it has been a while since I last touched on the problem of deploying software 
to a server, with that being said I have had a chance to really dig in and 
find a solution that is flexible as well as simple for developers to setup.

## The Idea

So when I started down this path of finding a clean deployment flow for my 
company ([The Control Group]) I had a few requirements It had to work for all of 
the different types of applications and languages that we build; I also did not
want to use web hooks they are just too clunky and you have to have a server that 
is accesible on the internet so it can be called (not really a fan); The last thing
that I wanted to be able to do is to deploy multiple versions of an application.

## Artifacts

Another part of this system is the need for storing build artifacts in our case 
tarballs containing all of the files need to run the system. for this I chose 
rackspace [Cloud Files], but Amazons [S3] would work just as well. it simply needs
to store our build artifacts for later downloading on to our server.

## I built a tool!!!

So now for the shameless plug! At first I implemented this system with a pretty
unwieldy bash script, and quickly realized if anyone else is going to use this
it needs to be simple to setup. With that I introduce [Dropship]! Dropship is 
a tool that is installed on your servers along with a simple configuration file
telling it where to get your artifact and how to install it as well being able
to sequentially update multiple servers.

Dropship uses md5sums to check freshness of your artifact comparing the one that
is installed with the sum of file on the artifact repo, it will then repeat this
process on the configured interval and if the sums do not match it will then start
the update process (pretty simple eh).

A [Dropship] config is and HCL file like the following:

```
# vim: set ft=hcl :
service "my-service" {
  # Use a semaphore to update one machine at a time
  sequentialUpdates = true

  # Check for updates every 10s
  checkInterval = "10s"

  # Run this command before update starts
  before "script" {
    command = "initctl my-service stop"
  }

  # Artifact defines what repository to use (rackspace) and where 
  # your artifact live on that repository
  artifact "s3" {
    bucket = "my-s3bucket"
    path = "my-service.tar.gz"
    destination = "./test/dest"
  }

  # After successful update send an event to graphite
  # this allows you to show deploy annotations in tools like grafana
  # 
  # The graphite hook will automatically add this services name into the 
  # graphite tags. You also have access to all of the services meta data
  # like Name, "current hash", hostname.
  after "graphite-event" {
    host = "http://<my-graphite-server>"
    tags = "deployment"
    what = "deployed to {{.Name}} on {{.Hostname}}"
    data = "{{.Hash}}"
  }

  # Run this command after the update finishes
  after "script" {
    command = "initctl my-service start"
  }
}
```

As you can see there are a bunch of options available for installing your system,
you can set hooks that will be called `before` and `after` your artifact is installed.

Hooks are a very interesting feature and I have implemented a few helpful hooks
to start with but hope to add many more. One hook worth mentioning is the
`graphite-event` hook this will create an event in graphite which can be viewed as
a pretty annotation on your graphs in grafana for example, you can then see how
your latest deployment affected your stats.

Currently this is available as a Debian package and can be installed by following 
the guide [here](https://github.com/ChrisMcKenzie/dropship#installation).

Please let me know what you think of this project in the comments. And feel free
to file issues and feature requests [here](https://github.com/ChrisMcKenzie/dropship/issues)

[The Control Group]: http://thecontrolgroup.com
[Cloud Files]: http://www.rackspace.com/cloud/files
[Dropship]: https://github.com/chrismckenzie/dropship
[S3]: https://aws.amazon.com/s3/
