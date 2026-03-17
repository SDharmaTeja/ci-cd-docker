package com.cicd.demo;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.*;
import java.time.Instant;
import java.util.Map;
import java.util.LinkedHashMap;

@RestController
@RequestMapping("/api")
public class AppController {

    @Value("${app.version:1.0.0}")
    private String appVersion;

    @Value("${app.name:demo-app}")
    private String appName;

    /**
     * Health check — called by Jenkins smoke test after deployment
     */
    @GetMapping("/health")
    public Map<String, Object> health() {
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("status",    "UP");
        response.put("service",   appName);
        response.put("version",   appVersion);
        response.put("timestamp", Instant.now().toString());
        return response;
    }

    /**
     * Info endpoint — returns deployment metadata
     */
    @GetMapping("/info")
    public Map<String, Object> info() {
        Map<String, Object> info = new LinkedHashMap<>();
        info.put("name",        appName);
        info.put("version",     appVersion);
        info.put("description", "CI/CD Demo Application");
        info.put("pipeline",    Map.of(
            "scm",      "GitLab",
            "ci",       "Jenkins",
            "artifacts","Nexus",
            "config",   "Chef"
        ));
        return info;
    }

    /**
     * Greeting endpoint — sample business logic
     */
    @GetMapping("/greet/{name}")
    public Map<String, String> greet(@PathVariable String name) {
        return Map.of(
            "message", "Hello, " + name + "! Deployed via CI/CD pipeline.",
            "version", appVersion
        );
    }
}
