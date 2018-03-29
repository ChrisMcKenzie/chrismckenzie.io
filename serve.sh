#!/bin/bash
# Serve the project.
hugo server -D --config=site.yaml --disableFastRender --watch $@
