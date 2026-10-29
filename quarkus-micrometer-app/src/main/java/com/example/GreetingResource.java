package com.example;

import io.micrometer.core.annotation.Counted;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Path("/hello")
public class GreetingResource {

    @GET
    @Produces(MediaType.TEXT_PLAIN)
    @Counted(value = "hello_requests", description = "Number of hello endpoint requests")
    public String hello() {
        return "Hello from Quarkus with Micrometer + OTel bridge!";
    }
}
