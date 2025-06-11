package main

import (
	"fmt"
	"log"
	"os"
	"strings"

	"gopkg.in/yaml.v3"
)

// KeyPath defines a path in the YAML structure to the specific field
// you want to update.
type KeyPath []string

// targetFields lists all YAML paths containing URLs that must be replaced.
var targetFields = []KeyPath{
	{"studio", "environment", "SUPABASE_PUBLIC_URL"},
	{"auth", "environment", "GOTRUE_SITE_URL"},
	{"auth", "environment", "API_EXTERNAL_URL"},
	{"rest", "environment", "POSTGREST_SITE_URL"},
	{"realtime", "environment", "PORTAL_URL"},
	{"storage", "environment", "FILE_STORAGE_BACKEND_URL"},
	{"kong", "environment", "SUPABASE_PUBLIC_URL"},
	{"kong", "environment", "SUPABASE_STUDIO_URL"},
}

// findAndUpdateValue walks a mapping node and replaces the value of the key
// specified by 'path' when it matches a string scalar containing the placeholders.
func findAndUpdateValue(node *yaml.Node, path KeyPath, fullDNS string) {
	// Only proceed if this node is a mapping (key/value pairs)
	if node.Kind != yaml.MappingNode {
		return
	}
	// Iterate children: even indices are keys, odd are values
	for i := 0; i < len(node.Content); i += 2 {
		keyNode := node.Content[i]
		valNode := node.Content[i+1]

		if keyNode.Value == path[0] {
			if len(path) == 1 {
				// We've reached the target field
				if valNode.Kind == yaml.ScalarNode && valNode.Tag == "!!str" {
					replaced := strings.ReplaceAll(valNode.Value, "REPLACEME.upcloudlb.com", fullDNS)
					replaced = strings.ReplaceAll(replaced, "example.com", fullDNS)
					valNode.Value = replaced
					valNode.Style = yaml.DoubleQuotedStyle
					log.Printf("Updated %s -> %s", strings.Join(path, "."), replaced)
				}
			} else {
				// Descend into the next level
				findAndUpdateValue(valNode, path[1:], fullDNS)
			}
		}
	}
}

func main() {
	if len(os.Args) != 4 {
		fmt.Println(`Usage:
			go run update_supabase_dns.go <input.yaml> <output.yaml> <lb-dns-prefix>

			Example:
			go run update_supabase_dns.go values.yaml updated.yaml lb-0a36988526c6443a947a8927f9190c0a-1

			How to find the prefix:
			kubectl get svc demo-supabase-kong \
				-o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
			// yields lb-xxx.upcloudlb.com; pass only the 'lb-xxx' part
		`)
		os.Exit(1)
	}

	inFile := os.Args[1]
	outFile := os.Args[2]
	dnsPrefix := os.Args[3]
	fullDNS := dnsPrefix + ".upcloudlb.com"

	// Read the YAML
	data, err := os.ReadFile(inFile)
	if err != nil {
		log.Fatalf("Failed to read %s: %v", inFile, err)
	}

	// Parse into a Node (AST)
	var root yaml.Node
	if err := yaml.Unmarshal(data, &root); err != nil {
		log.Fatalf("Failed to parse YAML: %v", err)
	}

	// The real document is the first child of the root (DocumentNode)
	if len(root.Content) < 1 {
		log.Fatal("No content in YAML document")
	}
	doc := root.Content[0]

	// Perform replacements on each target field
	for _, path := range targetFields {
		findAndUpdateValue(doc, path, fullDNS)
	}

	// Write the updated AST back to YAML
	out, err := os.Create(outFile)
	if err != nil {
		log.Fatalf("Cannot create %s: %v", outFile, err)
	}
	defer out.Close()

	enc := yaml.NewEncoder(out)
	enc.SetIndent(2)
	if err := enc.Encode(&root); err != nil {
		log.Fatalf("Failed to write YAML: %v", err)
	}

	fmt.Printf("Updated URLs to http://%s and wrote to %s\n", fullDNS, outFile)
}
