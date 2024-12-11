
#if defined(ICBRICKS)
#include <Arduino.h>
#include <stdio.h>
#include <stdlib.h>

#include "mem.h"
#include "interp.h"

#include "ICBricksI2cEquipment.h"
#include "ICBricks.h"
#include "ICBricks/MusicPlayer/playTone.h"

/*恢复主控器
 * 作用：
 * 1.扫描iic，并且关闭所有端口上输出设备
 * 2.恢复主控器电量对led的控制权(除了中间led)
 */
void RestoreMasterController()
{
    RestoreMainControllerState();
}

/*检查Gp脚本执行锁
*调用该函数会直到，函数内部条件触发;
* 执行 do{..}while(true) 直到循环被触发break;

*/
void checkGpScriptExecutionLock()
{
    do
    {
        ets_delay_us(10);
        
        // GpScriptControlState 该变量请勿在其他任务修改(写)，只可以访问(读)！
        if (GpScriptControlState == 0x01) //|| (ideConnected() || Serial.available()))
        {
            break;
        }
    } while (true);
}

/*退出脚本程序
 * 返回：
 * 0 不进行任何操作。
 * 1 退出程序
 */
uint8_t terminateGpScriptExecution()
{

    if (GpScriptControlState == 0x02)
    {
        RestoreMainControllerState();

        // esp_restart(); // esp系统软复位

        return 1;
    }
    return 0;
}

/*----------------------------------------------------------*/

// 打开IIC端口，作用让总线开关切换芯片把IIC总线切换到指定端口
OBJ primsOpenIICPort(int argCount, OBJ *args)
{
    enableI2CCommunication();
    if (!isInt(args[0]))
    {
        fail(needsIntegerError);
        return falseObj;
    }

    // 打开端口
    IIC_TCA9548APWR_Open(obj2int(args[0]));
    return falseObj;
}

OBJ primsGetEncoderData(int argCount, OBJ *args)
{
    enableI2CCommunication();
    if (!isInt(args[0]))
    {
        fail(needsIntegerError);
        return falseObj;
    }
    int port = obj2int(args[0]);
    IIC_DeviceAddress addre = (IIC_DeviceAddress)obj2int(args[1]);
    int mods = obj2int(args[2]);

    IIC_DeviceUpdates(port, addre);

    int16_t tempe = GetEncoderData(port, mods);

    if (mods == 1) // 获取按键状态
    {
        return ((tempe) ? trueObj : falseObj);
    }

    return int2obj(tempe);
}

OBJ primsGetGestures(int argCount, OBJ *args)
{
    enableI2CCommunication();
    if (!isInt(args[0]))
    {
        fail(needsIntegerError);
        return falseObj;
    }
    int port = obj2int(args[0]);
    IIC_DeviceAddress addre = (IIC_DeviceAddress)obj2int(args[1]);

    IIC_DeviceUpdates(port, addre);

    return int2obj(IIC_APDS9960_GetGesture(port));
}

OBJ primsVL53L0_Continue(int argCount, OBJ *args)
{
    enableI2CCommunication();
    if (!isInt(args[0]))
    {
        fail(needsIntegerError);
        return falseObj;
    }
    int port = obj2int(args[0]);
    IIC_DeviceAddress addre = (IIC_DeviceAddress)obj2int(args[1]);

    IIC_DeviceUpdates(port, addre);

    return int2obj(IIC_VL53L0_Continue(port));
}

// 获取获取陀螺仪轴
OBJ primsGyroscopeAxis(int argCount, OBJ *args)
{
    enableI2CCommunication();
    if (!isInt(args[0]))
    {
        fail(needsIntegerError);
        return falseObj;
    }
    int port = obj2int(args[0]);
    IIC_DeviceAddress addre = (IIC_DeviceAddress)obj2int(args[1]);
    int direction = obj2int(args[2]);

    IIC_DeviceUpdates(port, addre);

    return int2obj(Get_GyroscopeAxis(port, direction));
}

// 获取陀螺仪方向
OBJ primsGyroscopeOrientation(int argCount, OBJ *args)
{
    enableI2CCommunication();
    if (!isInt(args[0]))
    {
        fail(needsIntegerError);
        return falseObj;
    }
    int port = obj2int(args[0]);
    IIC_DeviceAddress addre = (IIC_DeviceAddress)obj2int(args[1]);
    int direction = obj2int(args[2]);

    IIC_DeviceUpdates(port, addre);

    return ((Get_GyroscopeOrientation(port, direction)) ? trueObj : falseObj);
}

OBJ primsSetControllerLED(int argCount, OBJ *args)
{
    if (!isInt(args[0]))
    {
        fail(needsIntegerError);
        return falseObj;
    }
    uint8_t ledstat = obj2int(args[0]);
    uint8_t ledr = obj2int(args[1]);
    uint8_t ledg = obj2int(args[2]);
    uint8_t ledb = obj2int(args[3]);

    // Serial.printf("\n r[%d] g%d b%d",ledr,ledg,ledb);

    if (ledstat)
    {
        SetPowerControlLED(false);
        for (int i = 0; i < 4; i++)
        {
            SetLEDColor(i, ledr, ledg, ledb);
            // leds_Colour[i].r = ledr;
            // leds_Colour[i].g = ledg;
            // leds_Colour[i].b = ledb;
        }
        RefreshLEDColor(); // 刷新LED
    }
    else
    {
        SetPowerControlLED(true);
    }

    return falseObj;
}

OBJ primsGetKeyPressStatus(int argCount, OBJ *args)
{
    if (!isInt(args[0]))
    {
        fail(needsIntegerError);
        return falseObj;
    }
    uint8_t keypin = obj2int(args[0]);
    bool sound = (bool)obj2int(args[1]);

    if (keypin)
    {
        if (ICBricks_GetKeyPressStatus(keypin, sound))
        {
            return trueObj;
        }
    }
    return falseObj;
}

OBJ primsPlayingNotes(int argCount, OBJ *args)
{
    if (!isInt(args[0]))
    {
        fail(needsIntegerError);
        return falseObj;
    }
    int sound = obj2int(args[0]);
    int duration = obj2int(args[1]);

    if (duration > 1)
    {
        playTone(sound, duration);
        // playNoteFrequency(sound, duration);
    }
    else if (duration) // 负数~ 1范围 自动播放
    {
        playTone(sound);
    }

    return falseObj;
}

OBJ primsNotesVolume(int argCount, OBJ *args)
{
    if (!isInt(args[0]))
    {
        fail(needsIntegerError);
        return falseObj;
    }
    int volu = obj2int(args[0]);

    ToneVolume(((volu > 0) ? volu : 0));

    return falseObj;
}

/*******************OUT***************************/
// 伺服电机-根据协议来控制
OBJ primsServoMotorControl(int argCount, OBJ *args)
{
    enableI2CCommunication();
    if (!isInt(args[0]))
    {
        fail(needsIntegerError);
        return falseObj;
    }

    int port = obj2int(args[0]);
    int reg = obj2int(args[1]);
    int speed = obj2int(args[2]);
    int tim = obj2int(args[3]);

    IIC_TCA9548APWR_Open(port);
    IIC_SERVO_MOTOR_Control(reg, speed, tim);

    return falseObj;
}

// 伺服电机-返回角度/速度....
OBJ primsreadServoInfo(int argCount, OBJ *args)
{
    enableI2CCommunication();
    if (!isInt(args[0]))
    {
        fail(needsIntegerError);
        return falseObj;
    }

    int port = obj2int(args[0]);
    int mods = obj2int(args[1]);

    long arr[4];
    IIC_TCA9548APWR_Open(port);

    /*
     * 0 速度
     * 1 位置
     * 2 功率
     * 3 标志位
     */
    IIC_SERVO_MOTOR_Read(arr);

    return int2obj(arr[mods]);
}

// 伺服电机等待执行完成
OBJ primsWaitForServoCompletion(int argCount, OBJ *args)
{
    enableI2CCommunication();
    if (!isInt(args[0]))
    {
        fail(needsIntegerError);
        return falseObj;
    }

    int port = obj2int(args[0]);

    static long read[4];
    static bool preceding = false;
    if (true)
    {
        IIC_TCA9548APWR_Open(port);
        IIC_SERVO_MOTOR_Read(read);

        if ((preceding && (!read[2] && read[3] == 11)) || read[3] == 10) // 堵转停止
        {
            return trueObj;
        }

        // 任意一个 拔下来 则退出
        if (!scanIICAddress(port,0x50))
        {
            return trueObj;
        }
        preceding = ((read[3] != 11) ? true : preceding);
        vTaskDelay(pdMS_TO_TICKS(10));
    }
    return falseObj;
}

// 直到 双伺服电机执行完毕
OBJ primsWaitForDualServoCompletion(int argCount, OBJ *args)
{
    
    enableI2CCommunication();
    if (!isInt(args[0]))
    {
        fail(needsIntegerError);
        return falseObj;
    }

    int portA = obj2int(args[0]);
    int portB = obj2int(args[1]);

    long Lread[4], Rread[4];
    bool preceding = false;

    while (true)
    {
        IIC_TCA9548APWR_Open(portA);
        IIC_SERVO_MOTOR_Read(Lread);
        IIC_TCA9548APWR_Open(portB);
        IIC_SERVO_MOTOR_Read(Rread);

        if ((preceding && (!Rread[2] && Rread[3] == 11)) || Rread[3] == 10) // 堵转停止
        {
            break;
        }

        if (((!Lread[2] && Lread[3] == 11)) || Lread[3] == 10) // 堵转停止
        {
            break;
        }

        // 任意一个 拔下来 则退出
        if (!scanIICAddress(portA,0x50) || !scanIICAddress(portB,0x50))
        {
            break;
        }
        preceding = ((Rread[3] != 11 || Lread[3] != 11) ? true : preceding);
        delay(10);
    }
     return trueObj;
}

OBJ primsI2cLed(int argCount, OBJ *args)
{
    enableI2CCommunication();
    if (!isInt(args[0]))
    {
        fail(needsIntegerError);
        return falseObj;
    }

    int port = obj2int(args[0]);
    int r = obj2int(args[1]);
    int g = obj2int(args[2]);
    int b = obj2int(args[3]);

    IIC_TCA9548APWR_Open(port);
    IIC_LED(r, g, b);

    return falseObj;
}

OBJ primsGetControllerVersion(int argCount, OBJ *args)
{
    if (!isInt(args[0]))
    {
        fail(needsIntegerError);
        return falseObj;
    }

    return int2obj(FIRMWARE_VERSION);
}

static PrimEntry entries[] = {
    {"OpenIICPort", primsOpenIICPort},
    // 获取编码器
    {"GetEncoderData", primsGetEncoderData},
    // 手势 接口行为描述：返回映射后手势 int
    {"GetGestures", primsGetGestures},
    // 返回测量距离值 int
    {"GetDistance", primsVL53L0_Continue},
    // 获取获取陀螺仪轴
    {"GyroscopeAxis", primsGyroscopeAxis},
    // 获取陀螺仪方向
    {"GyroscopeOrientation", primsGyroscopeOrientation},
    // 设置主控器led
    {"setControllerLED", primsSetControllerLED},
    // 获取按键状态 并且播放按键声音
    {"GetKeyPressStatus", primsGetKeyPressStatus},
    // 播放音符
    {"PlayingNotes", primsPlayingNotes},
    // 设置音量大小
    {"SetNotesVolume", primsNotesVolume},
    // led
    {"I2cLed", primsI2cLed},
    // 获取伺服信息
    {"readServoInfo", primsreadServoInfo},
    // 伺服电机等待执行完成
    {"WaitForServoCompletion",primsWaitForServoCompletion},
    // 直到 双伺服电机执行完毕
    {"WaitForDualServoCompletion",primsWaitForDualServoCompletion},
    // 伺服电机协议控制
    {"ServoMotorControl", primsServoMotorControl},
    // 获取主控器版本
    {"GetControllerVersion", primsGetControllerVersion},

};

void addICBricksPrims()
{
    addPrimitiveSet(ICBricksPrims, "ICBricks", sizeof(entries) / sizeof(PrimEntry), entries);
}
#endif