using Azure.Messaging.ServiceBus;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddControllers();
builder.Services.AddHealthChecks().AddCheck<SampleHealthCheck>("Sample");

// Learn more about configuring Swagger/OpenAPI at https://aka.ms/aspnetcore/swashbuckle
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();
app.MapHealthChecks("/health");

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();

app.UseAuthorization();

app.MapControllers();


// Service Bus client implementation
Console.WriteLine("Configuring queue client...");

var simulatedProcessingDurationInSeconds = int.Parse(Environment.GetEnvironmentVariable("SLEEP_DURATION_SEC"));

var clientOptions = new ServiceBusClientOptions()
{
    TransportType = ServiceBusTransportType.AmqpWebSockets
};
var client = new ServiceBusClient(Environment.GetEnvironmentVariable("NAMESPACE_CONNECTION_STRING"), clientOptions);

var processorOptions =  new ServiceBusProcessorOptions()
{
    ReceiveMode = ServiceBusReceiveMode.PeekLock
};
var processor = client.CreateProcessor(Environment.GetEnvironmentVariable("QUEUE_NAME"), processorOptions);

processor.ProcessMessageAsync += MessageHandler;
processor.ProcessErrorAsync += ErrorHandler;

Console.WriteLine("Listening to queue...");

await processor.StartProcessingAsync();

// handle received messages
async Task MessageHandler(ProcessMessageEventArgs args)
{
    string body = args.Message.Body.ToString();
    Console.WriteLine($"Message #{args.Message.MessageId} - Received - Processing ({simulatedProcessingDurationInSeconds} sec)");

    await Task.Delay(TimeSpan.FromSeconds(simulatedProcessingDurationInSeconds));

    Console.WriteLine($"Message #{args.Message.MessageId} - Processed");

    // complete the message. message is deleted from the queue. 
    await args.CompleteMessageAsync(args.Message);
}

// handle any errors when receiving messages
Task ErrorHandler(ProcessErrorEventArgs args)
{
    Console.WriteLine(args.Exception.ToString());
    return Task.CompletedTask;
}

app.Run();

