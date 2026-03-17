package com.cicd.demo;

import org.springframework.stereotype.Service;

@Service
public class GreetingService {

    /**
     * Formats a personalised greeting.
     * Kept simple so unit tests can demonstrate passing coverage.
     */
    public String greet(String name) {
        if (name == null || name.isBlank()) {
            throw new IllegalArgumentException("Name must not be blank");
        }
        return "Hello, " + name.trim() + "!";
    }

    /**
     * Validates semantic version string (major.minor.patch[-qualifier])
     */
    public boolean isValidVersion(String version) {
        if (version == null) return false;
        return version.matches("\\d+\\.\\d+\\.\\d+(-[A-Za-z0-9.]+)?");
    }
}
