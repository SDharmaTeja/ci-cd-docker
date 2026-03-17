package com.cicd.demo;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@AutoConfigureMockMvc
class DemoApplicationTests {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private GreetingService greetingService;

    // ---- GreetingService unit tests ----------------------------------------

    @Test
    @DisplayName("greet() returns proper greeting")
    void greetReturnsHello() {
        assertEquals("Hello, Alice!", greetingService.greet("Alice"));
    }

    @Test
    @DisplayName("greet() trims whitespace")
    void greetTrimmsWhitespace() {
        assertEquals("Hello, Bob!", greetingService.greet("  Bob  "));
    }

    @Test
    @DisplayName("greet() throws on blank name")
    void greetThrowsOnBlank() {
        assertThrows(IllegalArgumentException.class, () -> greetingService.greet(""));
    }

    @Test
    @DisplayName("isValidVersion() accepts correct semver")
    void validVersionAccepted() {
        assertTrue(greetingService.isValidVersion("1.0.0"));
        assertTrue(greetingService.isValidVersion("2.3.14-SNAPSHOT"));
        assertTrue(greetingService.isValidVersion("10.0.0-RC1"));
    }

    @Test
    @DisplayName("isValidVersion() rejects malformed versions")
    void invalidVersionRejected() {
        assertFalse(greetingService.isValidVersion(null));
        assertFalse(greetingService.isValidVersion("1.0"));
        assertFalse(greetingService.isValidVersion("v1.0.0"));
    }

    // ---- Controller integration tests --------------------------------------

    @Test
    @DisplayName("GET /api/health returns UP")
    void healthEndpointUp() throws Exception {
        mockMvc.perform(get("/api/health"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("UP"))
            .andExpect(jsonPath("$.service").exists())
            .andExpect(jsonPath("$.version").exists());
    }

    @Test
    @DisplayName("GET /api/greet/{name} returns greeting")
    void greetEndpoint() throws Exception {
        mockMvc.perform(get("/api/greet/World"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.message").value("Hello, World! Deployed via CI/CD pipeline."));
    }

    @Test
    @DisplayName("GET /api/info returns pipeline metadata")
    void infoEndpoint() throws Exception {
        mockMvc.perform(get("/api/info"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.pipeline.ci").value("Jenkins"))
            .andExpect(jsonPath("$.pipeline.scm").value("GitLab"));
    }
}
