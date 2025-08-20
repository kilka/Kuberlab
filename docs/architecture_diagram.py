#!/usr/bin/env python3
"""
OCR AKS Architecture Diagram
Generates architecture diagrams for the OCR processing system on Azure Kubernetes Service
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.azure.compute import AKS, ContainerInstances
from diagrams.azure.network import ApplicationGateway, VirtualNetworks, Subnets
from diagrams.azure.storage import BlobStorage, TableStorage
from diagrams.azure.integration import ServiceBus
from diagrams.azure.security import KeyVaults
from diagrams.azure.devops import Repos
from diagrams.azure.analytics import LogAnalyticsWorkspaces
from diagrams.azure.general import Helpsupport as Monitor
from diagrams.azure.identity import ManagedIdentities
from diagrams.azure.compute import ACR
from diagrams.onprem.client import Users
from diagrams.onprem.gitops import Flux
from diagrams.k8s.compute import Pod, Deployment
from diagrams.k8s.network import Service
from diagrams.programming.framework import FastAPI

# High-level architecture diagram  
with Diagram("OCR AKS Architecture", filename="diagrams/ocr_architecture", show=False, direction="TB"):
    
    # External users at the top
    users = Users("Users")
    
    with Cluster("Azure Subscription"):
        
        # Entry point - Application Gateway
        agc = ApplicationGateway("Application Gateway\nfor Containers")
        
        # Main AKS Cluster in center
        with Cluster("AKS Cluster"):
            
            # Core workloads
            with Cluster("ocr namespace"):
                api_svc = Service("API Service")
                api_pods = Pod("OCR API Pods\n(FastAPI)")
                worker_pods = Pod("OCR Worker Pods\n(Tesseract)")
                
            # Scaling components
            with Cluster("Autoscaling"):
                hpa = Pod("HPA")
                keda = Pod("KEDA")
                
            # Secret Management
            with Cluster("Secret Management"):
                eso = Pod("External Secrets\nOperator")
                
            # GitOps
            flux = Flux("Azure Flux\nExtension")
        
        # Left side - Identity & Security
        with Cluster("Identity & Security"):
            keyvault = KeyVaults("Key Vault")
            api_identity = ManagedIdentities("mi-api\n(SB Sender)")
            worker_identity = ManagedIdentities("mi-worker\n(SB Receiver)")
            alb_identity = ManagedIdentities("mi-alb\n(AGC Manager)")
        
        # Right side - Data Services
        with Cluster("Data Services"):
            with Cluster("Messaging"):
                servicebus = ServiceBus("Service Bus\nocr-jobs")
                poison_queue = ServiceBus("ocr-jobs-poison\n(Manual DLQ)")
            
            with Cluster("Storage"):
                blob = BlobStorage("Blob Storage\n(uploads/results)")
                table = TableStorage("Table Storage\n(Job Metadata)")
        
        # Bottom - Supporting Services
        with Cluster("Supporting Services"):
            acr = ACR("Container Registry")
            logs = LogAnalyticsWorkspaces("Log Analytics")
            insights = Monitor("Container Insights")
    
    # Connections - User flow
    users >> Edge(label="HTTPS", color="darkgreen") >> agc
    agc >> Edge(label="Routes to", color="darkgreen") >> api_svc
    api_svc >> Edge(color="darkgreen") >> api_pods
    
    # API workflow
    api_pods >> Edge(label="Queue job", color="blue") >> servicebus
    api_pods >> Edge(label="Upload", color="blue") >> blob
    api_pods >> Edge(label="Metadata", color="blue") >> table
    
    # Worker workflow  
    servicebus >> Edge(label="Poll", color="orange") >> worker_pods
    worker_pods >> Edge(label="Process", color="orange") >> blob
    worker_pods >> Edge(label="Update", color="orange") >> table
    servicebus >> Edge(label="DLQ", color="red", style="dashed") >> poison_queue
    
    # Identity flow
    api_pods >> Edge(label="Uses", style="dotted", color="purple") >> api_identity
    worker_pods >> Edge(label="Uses", style="dotted", color="purple") >> worker_identity
    agc >> Edge(label="Managed by", style="dotted", color="purple") >> alb_identity
    
    # Identity permissions
    api_identity >> Edge(label="SB Send", style="dotted", color="mediumpurple") >> servicebus
    worker_identity >> Edge(label="SB Receive", style="dotted", color="mediumpurple") >> servicebus
    worker_identity >> Edge(label="Storage Access", style="dotted", color="mediumpurple") >> blob
    alb_identity >> Edge(label="Manages", style="dotted", color="mediumpurple") >> agc
    
    # Secret management flow
    eso >> Edge(label="Fetches", style="dotted", color="darkviolet") >> keyvault
    eso >> Edge(label="Injects", style="dotted", color="darkviolet") >> api_pods
    eso >> Edge(label="Injects", style="dotted", color="darkviolet") >> worker_pods
    
    # Scaling
    hpa >> Edge(style="dotted", color="gray") >> api_pods
    keda >> Edge(style="dotted", color="gray") >> servicebus
    keda >> Edge(style="dotted", color="gray") >> worker_pods
    
    # Container images
    acr >> Edge(style="dotted", color="gray") >> api_pods
    acr >> Edge(style="dotted", color="gray") >> worker_pods
    
    # GitOps
    flux >> Edge(label="Deploys", style="dotted", color="darkgray") >> api_pods
    flux >> Edge(label="Deploys", style="dotted", color="darkgray") >> worker_pods
    flux >> Edge(label="Deploys", style="dotted", color="darkgray") >> eso
    
    # Monitoring
    api_pods >> Edge(style="dotted", color="lightgray") >> logs
    worker_pods >> Edge(style="dotted", color="lightgray") >> logs
    logs >> Edge(style="dotted", color="lightgray") >> insights

# Detailed Kubernetes architecture
with Diagram("OCR Kubernetes Detail", filename="diagrams/ocr_k8s_detail", show=False, direction="TB"):
    
    # External entry point
    agc_gw = ApplicationGateway("Application Gateway\nfor Containers")
    
    with Cluster("AKS Cluster"):
        
        # Control plane components
        with Cluster("Control Plane"):
            with Cluster("flux-system namespace"):
                flux_ctrl = Flux("Azure Flux Extension\nControllers")
                flux_kustomization = Pod("Kustomizations\n(3 layers)")
            
            with Cluster("keda namespace"):
                keda_operator = Pod("KEDA Operator")
                keda_metrics = Pod("KEDA Metrics Server")
            
            with Cluster("arc-system namespace"):
                alb = Pod("ALB Controller")
                
            with Cluster("external-secrets namespace"):
                eso = Pod("ESO Operator")
                eso_webhook = Pod("ESO Webhook")
                eso_cert = Pod("Cert Controller")
            
            with Cluster("kube-system namespace"):
                metrics_server = Pod("Metrics Server")
        
        # Application namespace
        with Cluster("ocr namespace"):
            
            # API workload
            with Cluster("API Workload"):
                api_service = Service("ocr-api-svc")
                api_deploy = Deployment("ocr-api")
                api_pod1 = Pod("api-pod-1")
                api_pod2 = Pod("api-pod-2")
                api_hpa = Pod("HPA")
                api_sa = Pod("ocr-api-sa\n(ServiceAccount)")
            
            # Worker workload
            with Cluster("Worker Workload"):
                worker_deploy = Deployment("ocr-worker")
                worker_pod1 = Pod("worker-pod-1")
                worker_pod2 = Pod("worker-pod-2")
                scaled_object = Pod("ScaledObject")
                trigger_auth = Pod("TriggerAuthentication")
                worker_sa = Pod("ocr-worker-sa\n(ServiceAccount)")
            
            # Configuration & Secrets
            with Cluster("Configuration"):
                external_secret = Pod("ExternalSecret\n(ocr-secrets)")
                secret_store = Pod("SecretStore\n(azure-keyvault)")
                cluster_config = Pod("cluster-config\n(Terraform handoff)")
                ocr_config = Pod("ocr-config\n(ConfigMap)")
    
    # Azure Resources
    with Cluster("Azure Resources"):
        kv = KeyVaults("Key Vault")
        sb = ServiceBus("Service Bus")
        storage = BlobStorage("Blob Storage")
    
    # Traffic flow
    agc_gw >> Edge(label="Routes to", color="darkgreen") >> api_service
    api_service >> Edge(label="Load balances", color="darkgreen") >> api_deploy
    api_deploy >> Edge(color="darkgreen") >> api_pod1
    api_deploy >> Edge(color="darkgreen") >> api_pod2
    
    # Scaling flows
    api_hpa >> Edge(label="Scales", style="dotted", color="blue") >> api_deploy
    metrics_server >> Edge(style="dotted", color="blue") >> api_hpa
    keda_operator >> Edge(style="dotted", color="orange") >> scaled_object
    scaled_object >> Edge(style="dotted", color="orange") >> trigger_auth
    trigger_auth >> Edge(style="dotted", color="orange") >> sb
    scaled_object >> Edge(label="Scales", style="dotted", color="orange") >> worker_deploy
    worker_deploy >> Edge(color="orange") >> worker_pod1
    worker_deploy >> Edge(color="orange") >> worker_pod2
    
    # Secret management
    eso >> Edge(style="dotted", color="purple") >> secret_store
    secret_store >> Edge(style="dotted", color="purple") >> kv
    eso >> Edge(style="dotted", color="purple") >> external_secret
    external_secret >> Edge(style="dotted", color="purple") >> api_deploy
    external_secret >> Edge(style="dotted", color="purple") >> worker_deploy
    
    # GitOps deployments with layers
    flux_ctrl >> Edge(label="Manages", style="dotted", color="gray") >> flux_kustomization
    flux_kustomization >> Edge(label="Deploys", style="dotted", color="darkslategray") >> eso
    flux_kustomization >> Edge(label="Deploys", style="dotted", color="darkslategray") >> keda_operator
    flux_kustomization >> Edge(label="Deploys", style="dotted", color="darkslategray") >> alb
    flux_kustomization >> Edge(label="Deploys", style="dotted", color="darkslategray") >> api_deploy
    flux_kustomization >> Edge(label="Deploys", style="dotted", color="darkslategray") >> worker_deploy
    flux_kustomization >> Edge(label="Configures", style="dotted", color="darkslategray") >> external_secret
    cluster_config >> Edge(label="Variables", style="dashed", color="darkorange") >> flux_kustomization
    
    # ServiceAccount connections
    api_deploy >> Edge(label="Uses", style="dotted", color="brown") >> api_sa
    worker_deploy >> Edge(label="Uses", style="dotted", color="brown") >> worker_sa
    
    # Application data flow
    api_pod1 >> Edge(label="Queue job", style="dashed", color="blue") >> sb
    api_pod2 >> Edge(label="Queue job", style="dashed", color="blue") >> sb
    api_pod1 >> Edge(label="Upload", style="dashed", color="blue") >> storage
    api_pod2 >> Edge(label="Upload", style="dashed", color="blue") >> storage
    
    worker_pod1 >> Edge(label="Poll", style="dashed", color="red") >> sb
    worker_pod2 >> Edge(label="Poll", style="dashed", color="red") >> sb
    worker_pod1 >> Edge(label="Read/Write", style="dashed", color="red") >> storage
    worker_pod2 >> Edge(label="Read/Write", style="dashed", color="red") >> storage

# CI/CD Pipeline diagram (PLANNED - NOT YET IMPLEMENTED)
with Diagram("OCR CI/CD Pipeline (Future State)", filename="diagrams/ocr_cicd_planned", show=False, direction="LR"):
    
    developer = Users("Developer")
    
    with Cluster("Current State (Manual)"):
        local_build = ContainerInstances("Local Build\n(manage-images.sh)")
        manual_push = ContainerInstances("Manual Push\nto ACR")
        manual_deploy = ContainerInstances("make deploy")
    
    with Cluster("GitHub (Planned)"):
        repo = Repos("kilka/Kuberlab")
        actions = Repos("GitHub Actions\n(To be created)")
        oidc = ManagedIdentities("GitHub OIDC\n(Configured)")
    
    with Cluster("Build Pipeline (Planned)"):
        build = ContainerInstances("Build & Test")
        scan = ContainerInstances("Trivy Scan")
        push = ContainerInstances("Push Images")
    
    with Cluster("Deploy Pipeline (Planned)"):
        terraform = ContainerInstances("Terraform Apply")
        flux_sync = Flux("Flux Sync")
        smoke_test = ContainerInstances("Smoke Tests")
    
    with Cluster("Azure Environment (Active)"):
        registry = ACR("Container Registry")
        cluster = AKS("AKS Cluster") 
        flux_ext = Flux("Azure Flux Extension")
        workload = Pod("OCR Workloads")
    
    # Current manual flow
    developer >> Edge(label="manual", color="red", style="bold") >> local_build
    local_build >> Edge(color="red", style="bold") >> manual_push
    manual_push >> Edge(color="red", style="bold") >> registry
    developer >> Edge(label="make deploy", color="red", style="bold") >> manual_deploy
    manual_deploy >> Edge(color="red", style="bold") >> cluster
    
    # Planned automated flow
    developer >> Edge(label="git push", color="darkgreen", style="dashed") >> repo
    repo >> Edge(label="Webhook", color="darkgreen", style="dashed") >> actions
    
    # Planned CI flow
    actions >> Edge(label="Run CI", color="blue", style="dashed") >> build
    build >> Edge(color="blue", style="dashed") >> scan
    scan >> Edge(color="blue", style="dashed") >> push
    push >> Edge(label="Docker images", color="blue", style="dashed") >> registry
    
    # Authentication (ready)
    actions >> Edge(label="OIDC ready", color="purple", style="dotted") >> oidc
    
    # Planned CD flow
    oidc >> Edge(label="Auth", color="orange", style="dashed") >> terraform
    terraform >> Edge(label="Provision infra", color="orange", style="dashed") >> cluster
    terraform >> Edge(label="Bootstrap", color="orange", style="dashed") >> flux_sync
    flux_sync >> Edge(label="Deploy apps", color="orange", style="dashed") >> workload
    
    # Current GitOps (active)
    cluster >> Edge(label="Active now", color="green", style="bold") >> flux_ext
    flux_ext >> Edge(label="Syncs from Git", color="green", style="bold") >> workload
    
    # Planned testing
    workload << Edge(label="Validate", color="gray", style="dashed") >> smoke_test
    smoke_test << Edge(color="gray", style="dashed") >> actions

# Simple end-to-end OCR flow diagram - Minimal and clean
with Diagram("OCR Processing Flow", filename="diagrams/ocr_simple_flow", show=False, direction="LR",
             graph_attr={"bgcolor": "white", "pad": "0.5", "ranksep": "1.8", "nodesep": "0.8"}):
    
    # User on the left
    user = Users("User")
    
    # Gateway
    gateway = ApplicationGateway("Gateway")
    
    # Main processing in Kubernetes
    with Cluster("AKS", graph_attr={"bgcolor": "#e8f4fd"}):
        api = Pod("API")
        worker = Pod("Worker")
    
    # Azure Services on the right
    with Cluster("Azure", graph_attr={"bgcolor": "#fff4e6"}):
        queue = ServiceBus("Queue")
        blob = BlobStorage("Blob")
        table = TableStorage("Table")
    
    # Minimal flows with bidirectional arrows where applicable
    # User <-> Gateway <-> API (bidirectional for submit/response)
    user >> Edge(color="darkgreen") << gateway
    gateway >> Edge(color="darkgreen") << api
    
    # API interactions with Azure services
    api >> Edge(color="blue") >> queue
    api >> Edge(color="blue") << blob  # Bidirectional: save image, get result
    api >> Edge(color="blue") << table  # Bidirectional: create/check status
    
    # Worker processing
    queue >> Edge(color="orange") >> worker
    worker >> Edge(color="orange") << blob  # Bidirectional: get image, save result
    worker >> Edge(color="orange") >> table  # Update status

print("Architecture diagrams generated successfully!")
print("Generated files:")
print("  - diagrams/ocr_architecture.png - High-level architecture")
print("  - diagrams/ocr_k8s_detail.png - Detailed Kubernetes components")
print("  - diagrams/ocr_cicd_planned.png - CI/CD pipeline (future state)")
print("  - diagrams/ocr_simple_flow.png - Simple end-to-end OCR processing flow")