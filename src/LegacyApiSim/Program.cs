var builder = WebApplication.CreateBuilder(args);

var app = builder.Build();

app.MapGet("/legacy/status", () => Results.Ok(new
{
    system = "Legacy ERP",
    status = "Online",
    timestampUtc = DateTime.UtcNow
}));

app.MapGet("/legacy/customers", () => Results.Ok(new[]
{
    new { customerId = "C1000", name = "Contoso Manufacturing", tier = "Gold" },
    new { customerId = "C1001", name = "Fabrikam Retail", tier = "Silver" },
    new { customerId = "C1002", name = "Northwind Logistics", tier = "Bronze" }
}));

app.Run("http://0.0.0.0:5000");
