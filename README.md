# How to deploy supabase environment in kubernetes
```sh
cd supabase
./deploy_supabase.sh es-mad1 app1   # ./deploy_supabase.sh REGION APP_NAME
```

Make sure the script finishes successfully

# How to login the studio UI
The deployment script will output the end point and the user/pwd that you will use to connect:
```sh
Public endpoint: http://lb-0a3d0c515fa34dfb8b3af33ced93fbae-1.upcloudlb.com:8000
Kubernetes Namespace: kube-paas-fi-hel1-app1
Dashboard username: supabase
Dashboard password: jFEkLb37QeJtVT6
```

# Implementation
The script will deploy a supabase backend in a kubernetes cluster.
The script will create the kubernetes cluster if it does not exists one in the selected area.
The script will create a permanent volume and corresponding claim so the database is persisted.
The script will change all the default keys used in supabase as advice here: https://supabase.com/docs/guides/self-hosting/docker#generate-api-keys
The script will output the KUBECONFIG so users can connect and inspect the cluster
The script will output the endpoint to connect to the studio ui and the generated user/pwd (Dashboard username and Dashboard password)
The script will output also variables needed for client apps to connect to the supabase backend: JWT_SECRET, ANON_KEY and SERVICE_ROLE_KEY

# Current problems
You might get a problem generating the private network that the kubernetes cluster uses. Apparently we can't creeate 2 private networks with the same address even in different regions in the same account. If you get an error related to this, go to the deploy_supabase.sh script and change the address values: address=10.0.3.0/24

There is an issue when deploying 2 supabase instances in the same region, the second one fails to deploy because the load balancer name collides. The load balancer names actually look like malformed. I haven't been able to figure out how these names are created and this will need a second look.

If we fix the problem with the LB names we can potentially deploy more than one supabase in the same cluster. There is no work done to ensure security and isolation of more than one supabase deployment within one cluster

# Improvements
Namespace is unique per region and app name - Implement mechanisms to make sure that only the owner of the namespace can access it. For instance, to avoid a different user do helm install with the same namespace as other user, overwriting somebody else's deployment.

When creating the kubernetes cluster the script allows any IP address to access the cluster. We need to think the best way to do this.

Improve isolation between supabases inside the same kubernetes cluster

Set email env variables so supabase can send emails. For instance confirmation emails when creating a user

## Notes

Added as a project resource the Helm charts from 'https://github.com/supabase-community/supabase-kubernetes/tree/main'. We want to have a stable copy of the charts in our project. Upgrading must be taking into account in the future.

'values.examples.yaml' has some changes to make easier the configuration. I am using a go script to change the urls later in this file but it might be overengineer and it would suffice to have a variable for the URL that is later changed by the sed. This will be a future improvement



