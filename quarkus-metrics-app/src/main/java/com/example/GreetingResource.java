package com.example;

import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.metrics.LongCounter;
import io.opentelemetry.api.metrics.Meter;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Path("/hello")
public class GreetingResource {

    private final LongCounter requestCounter;

    @Inject
    public GreetingResource(OpenTelemetry openTelemetry) {
        Meter meter = openTelemetry.getMeter("com.example.quarkus-metrics-app");
        this.requestCounter = meter.counterBuilder("hello_requests")
                .setDescription("Number of hello requests")
                .setUnit("1")
                .build();
    }

    @GET
    @Produces(MediaType.TEXT_PLAIN)
    public String hello() {
        requestCounter.add(1);
        return "Hello from Quarkus with OpenTelemetry!";
    }
}
