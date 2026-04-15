var builder = WebApplication.CreateBuilder(args);

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI();

app.MapGet("/hello", () => Results.Ok(new
{
    message = "Hello from Web API",
    timestampUtc = DateTime.UtcNow
}))
.WithName("GetHello")
.WithOpenApi();

app.MapGet("/products", () => Results.Ok(new[]
{
    new { id = "P100", name = "Coffee Mug", price = 12.99m },
    new { id = "P101", name = "Notebook", price = 8.49m },
    new { id = "P102", name = "Headphones", price = 59.00m }
}))
.WithName("GetProductsV1")
.WithOpenApi();

app.MapGet("/v2/products", () => Results.Ok(new[]
{
    new { sku = "P100", name = "Coffee Mug", unitPrice = 12.99m, category = "Home" },
    new { sku = "P101", name = "Notebook", unitPrice = 8.49m, category = "Office" },
    new { sku = "P102", name = "Headphones", unitPrice = 59.00m, category = "Electronics" }
}))
.WithName("GetProductsV2")
.WithOpenApi();

app.MapGet("/admin/health", (HttpRequest request) =>
{
    var role = request.Headers["x-apim-caller-roles"].ToString();
    return Results.Ok(new
    {
        status = "Healthy",
        checkedAtUtc = DateTime.UtcNow,
        callerRoles = role
    });
})
.WithName("GetAdminHealth")
.WithOpenApi();

app.Run();
