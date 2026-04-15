using System.Net;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;

namespace FunctionApi;

public class HelloFunctions
{
    [Function("Hello")]
    public async Task<HttpResponseData> Hello(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "hello")] HttpRequestData req)
    {
        var response = req.CreateResponse(HttpStatusCode.OK);

        var caller = new
        {
            objectId = req.Headers.TryGetValues("x-apim-caller-oid", out var oid) ? oid.FirstOrDefault() : null,
            roles = req.Headers.TryGetValues("x-apim-caller-roles", out var roles) ? roles.FirstOrDefault() : null
        };

        await response.WriteAsJsonAsync(new
        {
            message = "Hello from Function API",
            timestampUtc = DateTime.UtcNow,
            caller
        });

        return response;
    }

    [Function("Orders")]
    public async Task<HttpResponseData> Orders(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "orders")] HttpRequestData req)
    {
        var response = req.CreateResponse(HttpStatusCode.OK);

        var orders = new[]
        {
            new { orderId = "A100", amount = 120.50m, status = "Processing" },
            new { orderId = "A101", amount = 75.00m, status = "Shipped" },
            new { orderId = "A102", amount = 42.99m, status = "Delivered" }
        };

        await response.WriteAsJsonAsync(new
        {
            count = orders.Length,
            items = orders
        });

        return response;
    }
}
