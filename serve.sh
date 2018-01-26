#!/bin/bash
# Serve the project.
hugo server --config=site.yaml --disableFastRender --watch $@
