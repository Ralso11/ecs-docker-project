# ECS Docker Project

📖 Want the full, beginner-friendly walkthrough of every step, command,
and decision made in this project? See
[PROJECT_GUIDE.md](./PROJECT_GUIDE.md).

## What is this project, in one sentence?

A small Flask web app, packaged as a Docker container, automatically
built and deployed to AWS ECS (Fargate) through a CI/CD pipeline —
turning "the app runs on my computer" into "the app runs, packaged
identically, on AWS, on demand."

## Why this project exists

The fourth project in this series, chosen specifically because
**Docker and containers were the most consistently requested skill**
across remote cloud/DevOps job postings researched — a gap none of the
first three projects (static site, serverless API, VPC networking)
covered. It also connects naturally to the Kubernetes/k3s work in an
existing homelab repo — this project is the AWS-managed counterpart to
that self-hosted setup.

## Architecture

```
Dockerfile + app code
        |  (pipeline builds the image)
       ECR  (stores the image)
        |  (ECS pulls from here)
Task Definition ("run this image, this much CPU/RAM, this port")
        |
    Service (Fargate — keeps it running, no servers to manage)
        |
  Reachable via a public IP in a VPC public subnet
```

- **Flask app** — a minimal Python web app returning a JSON message.
- **Docker / Dockerfile** — packages the app and everything it needs to
  run into one portable image.
- **ECR (Elastic Container Registry)** — AWS's private storage for
  Docker images, the "shelf" the pipeline pushes to and ECS pulls from.
- **ECS on Fargate** — runs the container without managing any
  underlying servers; AWS handles that invisibly.
- **VPC + public subnet + security group** — same networking pattern as
  the third project, opened on port 8080 (the app's port) instead of
  22/80.
- **IAM execution role** — a separate identity ECS itself uses to pull
  images and write logs (not the app's own identity).

## Problems & fixes — quick reference

| Problem | Why it happened | How it was fixed |
|---|---|---|
| Several terminal paste corruptions while writing `main.tf` | Long multi-line heredoc pastes repeatedly got cut off mid-write in Git Bash | Switched to generating the file and downloading it directly, avoiding the terminal paste step entirely for long files |
| Pipeline failed: `UnauthorizedOperation` on `ec2:CreateTags`, plus a CloudWatch Logs `AccessDenied` | Only ECR/ECS managed policies were attached to the deploying IAM user, but `main.tf` also creates a VPC (EC2/VPC permissions) and a CloudWatch log group — two entirely different AWS services that were simply forgotten when picking policies | Added `AmazonVPCFullAccess` and `CloudWatchLogsFullAccess` to the IAM user |

## Cost management: destroy on demand

Like the VPC project, this one isn't left running continuously — AWS
Fargate bills for CPU/memory reservation while a task is running, and
this AWS account is on the newer, credit-based free plan rather than
unlimited always-free usage. A separate `destroy.yml` workflow
(manually triggered, same approval gate as deployment) tears everything
down after each verification; redeploying is one click via the main
pipeline or a new push.

## How to reproduce this project

1. Install Git, Docker (optional, for local testing), Terraform.
2. Create a GitHub repo, clone it locally.
3. Write a small app (`app/app.py`) and its `Dockerfile`.
4. Write Terraform for: VPC + public subnet + security group, an ECR
   repository, an ECS cluster, an IAM execution role, a task definition
   referencing the ECR image, and a service running it on Fargate.
5. Create a dedicated IAM user. Before picking policies, list every
   distinct AWS service your Terraform touches (in this project: EC2/
   VPC, ECR, ECS, CloudWatch Logs, IAM) and make sure each is covered.
6. Store the keys as GitHub Secrets, set up a protected `production`
   environment with required reviewers.
7. Write a pipeline that: plans/applies the infrastructure, builds the
   Docker image, pushes it to ECR, then forces the ECS service to
   redeploy with the new image.
8. Push, approve, test the live public IP — then destroy when done.

## What's next (possible future additions)

- [ ] Add an Application Load Balancer in front of the service, for a
      stable URL instead of a changing task IP.
- [ ] Add a health check endpoint and configure ECS to use it.
- [ ] Push a second image tag on every commit (not just `:latest`) for
      proper version history and rollback capability.
