#!/bin/bash

gitlab-runner register \
    --non-interactive \
    --name $(hostname) \
    --url $(curl http://metadata.google.internal/computeMetadata/v1/instance/attributes/gitlab_url -H "Metadata-Flavor: Google") \
    --registration-token $(curl http://metadata.google.internal/computeMetadata/v1/instance/attributes/gitlab_token -H "Metadata-Flavor: Google") \
    --executor docker \
    --docker-image "docker:19.03.13" \
    --docker-privileged \
    --docker-volumes /var/run/docker.sock:/var/run/docker.sock \
    --tag-list globalsoft \
    --run-untagged=True \
    --locked=False