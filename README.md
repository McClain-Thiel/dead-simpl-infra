# dead-simpl-infra

Infrastructure code for Dead Simpl environments.

## CI/CD

The `clouddeploy` directory defines a Google Cloud Deploy pipeline with staging and production targets.

Use `cloudbuild.backend.yaml` and `cloudbuild.frontend.yaml` in the application repositories to build images and create Cloud Deploy releases.
