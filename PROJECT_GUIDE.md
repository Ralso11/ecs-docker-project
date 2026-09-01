# The Complete Guide to This Project
### (Written so anyone, even with zero background, can understand it)

This is the fourth project in a small portfolio series. It assumes the
basics from the first project's guide (Git, GitHub, Terraform, CI/CD)
are already familiar. This one is entirely about **containers** —
packaging an app so it runs identically anywhere.

---

## Part 1 — What problem does Docker actually solve?

"It works on my machine" is one of the most common frustrations in
software: an app runs fine for one person, then breaks for someone else
because of a different operating system, a missing dependency, or a
different software version.

**Docker solves this by packaging the app together with everything it
needs** — the code, the exact Python version, the exact libraries — into
one self-contained unit called a **container image**. That image runs
identically whether it's on your laptop, a coworker's laptop, or a
server in AWS, because it's not relying on whatever happens to already
be installed on that machine.

## Part 2 — The pieces of this project, and how they connect

```
Flask app code  +  Dockerfile
        |
        |  docker build  (creates an image)
        v
   Docker Image
        |
        |  docker push  (uploads it)
        v
    ECR  (AWS's private image storage)
        |
        |  ECS pulls it from here
        v
  Task Definition  (blueprint: this image, this much CPU/RAM, this port)
        |
        v
     Service  (keeps it running, on Fargate)
        |
        v
  Reachable at a public IP
```

## Part 3 — The Flask app and Dockerfile, explained

**`app/app.py`:**
```python
from flask import Flask
app = Flask(__name__)

@app.route("/")
def home():
    return {"message": "...", "status": "healthy"}

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
```
Flask is a small, beginner-friendly Python web framework. The important
detail here is `host="0.0.0.0"` — this means "accept requests from
anywhere," not just from inside the container itself. Without it, the
app would only respond to requests from within its own container, and
nothing outside — including ECS's networking — could ever reach it.

**`app/Dockerfile`:**
```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8080
CMD ["python", "app.py"]
```
Read top to bottom, like a recipe:
1. **`FROM python:3.12-slim`** — start from a minimal official Python
   image (`slim` = smaller, faster to download, fewer unnecessary tools).
2. **`WORKDIR /app`** — set the working folder inside the container.
3. **`COPY requirements.txt .`** then **`RUN pip install ...`** —
   install dependencies *before* copying the actual app code. This
   ordering is a deliberate Docker best practice: if only your app code
   changes later (not your dependencies), Docker can reuse the
   already-built "dependencies installed" step and rebuild faster.
4. **`COPY app.py .`** — copy the actual app code in.
5. **`EXPOSE 8080`** — documents which port the container listens on
   (informational — the real "make it reachable" step happens later, in
   the ECS/networking setup).
6. **`CMD [...]`** — the command that actually runs when the container
   starts.

## Part 4 — The Terraform files, explained

Same overall pattern as the previous projects. The new pieces are all in
`main.tf`, organized into four sections.

### Section 1: Networking
Identical concept to the third project (VPC, public subnet, internet
gateway, route table) — the only difference is the security group opens
port 8080 (the app's port) instead of 22/80.

### Section 2: Container Registry (ECR)
```hcl
resource "aws_ecr_repository" "app" {
  name                  = "${var.project_name}-app"
  image_tag_mutability  = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}
```
Creates the storage "shelf" for your Docker images.
`image_tag_mutability = "MUTABLE"` allows reusing tags like `latest`
(simpler for a learning project — production setups often use
`IMMUTABLE` with unique tags per build instead, for stricter version
tracking). `scan_on_push` automatically checks every uploaded image for
known security vulnerabilities, at no extra cost.

### Section 3: ECS Cluster, Logging, and the Execution Role
```hcl
resource "aws_ecs_cluster" "main" { ... }
resource "aws_cloudwatch_log_group" "app" {
  retention_in_days = 7
}
resource "aws_iam_role" "ecs_execution" { ... }
```
The cluster is mostly an organizational grouping — with Fargate, there's
no server capacity to actually manage inside it. The log group is where
your app's console output goes, auto-deleting after a week to keep
things tidy. The IAM role here is a separate identity that **ECS itself**
uses (not your app) — to pull images from ECR and write to the log
group. This is similar in spirit to the Lambda project's execution
role: an identity for the *platform* to act on your behalf, distinct
from any human user's credentials.

### Section 4: Task Definition and Service
```hcl
resource "aws_ecs_task_definition" "app" {
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu     # 256 = 0.25 vCPU
  memory                   = var.task_memory  # 512 MB
  container_definitions = jsonencode([{
    image = "${aws_ecr_repository.app.repository_url}:latest"
    portMappings = [{ containerPort = var.container_port }]
    logConfiguration = { ... }
  }])
}

resource "aws_ecs_service" "app" {
  desired_count = 1
  launch_type   = "FARGATE"
  network_configuration {
    subnets          = [aws_subnet.public.id]
    assign_public_ip = true
  }
}
```
The **task definition** is the blueprint — "run this exact image, with
this much CPU and memory, on this port, sending logs here." The
**service** is what actually keeps it running: `desired_count = 1`
means "always keep exactly one copy alive," and if it ever crashes, ECS
restarts it automatically. `assign_public_ip = true` is what makes it
reachable from your browser at all.

## Part 5 — The pipeline: build, push, deploy

This pipeline does more than any previous project's, because containers
add two genuinely new steps beyond "apply the infrastructure":

```yaml
- name: Log in to ECR
  run: aws ecr get-login-password ... | docker login ...

- name: Build Docker image
  run: docker build -t <ecr-url>:latest .

- name: Push Docker image to ECR
  run: docker push <ecr-url>:latest

- name: Force ECS to deploy the new image
  run: aws ecs update-service --force-new-deployment ...
```

- **Log in to ECR** — Docker needs to prove it's allowed to push images
  to your private registry; this fetches a temporary authentication
  token from AWS and feeds it to `docker login`.
- **Build** — runs the actual `docker build` command, using the
  Dockerfile in the `app/` folder, tagging the result with your ECR
  repository's address.
- **Push** — uploads that built image to ECR.
- **Force new deployment — the easy-to-miss step:** pushing a new image
  to ECR does **not** automatically make the running service switch to
  it. ECS keeps running whatever it was already running until
  explicitly told otherwise. This command is that explicit instruction:
  "go pull the latest image and redeploy." Forgetting this step is a
  common real-world mistake — the pipeline would appear to succeed, but
  the live app would silently keep running old code.

## Part 6 — The IAM permissions gap (a genuine "forgot a service" lesson)

The first deployment attempt attached only two managed policies:
`AmazonEC2ContainerRegistryFullAccess` and `AmazonECS_FullAccess` —
covering ECR and ECS. It failed with two separate `AccessDenied`/
`UnauthorizedOperation` errors: one creating the VPC (`ec2:CreateTags`),
one setting the CloudWatch log group's retention policy.

**Why this happened:** this project's `main.tf` actually touches *four*
distinct AWS services — EC2/VPC (networking), ECR (image storage), ECS
(running the container), and CloudWatch Logs (logging) — plus IAM (the
execution role). It's easy, when focused on "the ECS project," to only
think about the ECS-related policy and forget the supporting services
your own Terraform code also creates.

**The fix, and the habit worth keeping:** `AmazonVPCFullAccess` and
`CloudWatchLogsFullAccess` were added. Going forward, a good practice
before picking IAM policies for any project: actually scan your own
`main.tf` for every distinct `resource` type prefix (`aws_vpc`,
`aws_ecr_*`, `aws_ecs_*`, `aws_cloudwatch_*`, `aws_iam_*`) and make sure
each one has a matching permission — rather than assuming the
"headline" service's policy covers everything.

## Part 7 — A terminal lesson repeated, and the fix that stuck

While writing `main.tf`, several long multi-line pastes into Git Bash
got cut off mid-write (the same class of issue from earlier projects).
Rather than keep fighting the terminal, the file was generated directly
and downloaded, then dragged into the project folder — completely
sidestepping the paste-corruption risk for any file long enough to be
risky. Worth remembering as a general rule: if a terminal keeps
mangling long pastes, stop retrying the same approach and switch
methods entirely, rather than assuming the tenth attempt will work
where the first nine didn't.

## Part 8 — Cost management: why this gets destroyed after each check

Same reasoning as the third project: this AWS account uses the newer,
credit-based free plan, and AWS Fargate bills for reserved CPU/memory
while a task is running — not something to leave running indefinitely
without a reason. A second workflow, `destroy.yml`, triggered manually
(`workflow_dispatch`), tears the whole thing down on demand; the main
pipeline brings it back just as easily whenever it's actually needed.

## Part 9 — Command/concept glossary (new items vs previous projects)

| Term | Plain-language meaning |
|---|---|
| Docker image | A packaged, self-contained snapshot of an app and everything it needs to run |
| Container | A running instance of a Docker image |
| Dockerfile | The recipe describing how to build a Docker image |
| ECR | AWS's private storage service for Docker images |
| ECS | AWS's service for actually running containers |
| Fargate | An ECS mode where AWS manages the underlying servers invisibly — no EC2 instances to patch or size yourself |
| Task Definition | The blueprint describing one running container: image, CPU/memory, port |
| Service (ECS) | Keeps a task running continuously, restarting it if it crashes |
| Execution role | The identity ECS itself uses to pull images and write logs, separate from the app's own permissions |

## Part 10 — How to explain this project in an interview

> "I containerized a small Flask app with Docker and deployed it to AWS
> ECS using Fargate, so there's no server for me to manage directly. The
> whole thing — from building the Docker image to pushing it to ECR to
> deploying it on ECS — runs through a GitHub Actions pipeline with
> manual approval before anything real happens. I hit a real permissions
> gap along the way: I'd only granted IAM permissions for ECR and ECS,
> forgetting that my own Terraform code also touched VPC networking and
> CloudWatch logging — a good reminder to actually check every AWS
> service your infrastructure code touches, not just the headline one.
> I also made sure the pipeline explicitly forces ECS to redeploy after
> pushing a new image, since that doesn't happen automatically."

That story shows real container fundamentals plus the same
troubleshooting judgment demonstrated across the rest of the portfolio.

---

*This document, together with the repo's README.md, covers everything
needed to fully understand, explain, and rebuild this project.*
